// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "./interfaces/ICredentialAdapter.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {SatisfyTypes} from "./types/SatisfyTypes.sol";
import {Ownable} from "./utils/Ownable.sol";

contract SatisfyPolicyEngine is IPolicyEngine, Ownable {
    struct Policy {
        SatisfyTypes.LogicOp logic;
        uint64 startTime;
        uint64 endTime;
        bool active;
        SatisfyTypes.Predicate[] predicates;
    }

    mapping(bytes32 => address) public adapters;
    mapping(uint256 => Policy) private policies;
    mapping(address => bool) public authorizedConsumers;
    mapping(bytes32 => bool) public nullifierUsed;

    uint256 public policyCount;
    uint64 public currentEpoch;

    error EmptyPolicy();
    error InvalidAdapter();
    error InvalidAdapterId();
    error InvalidEpoch();
    error InvalidPolicyWindow();
    error NotAuthorizedConsumer();
    error NullifierAlreadyUsed(bytes32 replayKey);
    error PolicyCheckFailed(uint256 policyId);
    error PolicyDoesNotExist(uint256 policyId);
    error PolicyInactive(uint256 policyId);

    event AdapterRegistered(bytes32 indexed adapterId, address indexed adapter);
    event AuthorizedConsumerUpdated(address indexed consumer, bool allowed);
    event EpochUpdated(uint64 previousEpoch, uint64 newEpoch);
    event PolicyActiveUpdated(uint256 indexed policyId, bool active);
    event PolicyCreated(
        uint256 indexed policyId,
        SatisfyTypes.LogicOp logic,
        uint64 startTime,
        uint64 endTime,
        bool active,
        uint256 predicateCount
    );
    event PolicyWindowUpdated(uint256 indexed policyId, uint64 startTime, uint64 endTime);
    event ProofConsumed(uint256 indexed policyId, address indexed user, bytes32 indexed replayKey, bytes32 nullifier);

    modifier onlyAuthorizedConsumer() {
        if (!authorizedConsumers[msg.sender]) revert NotAuthorizedConsumer();
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {
        currentEpoch = 1;
        authorizedConsumers[initialOwner] = true;
        emit AuthorizedConsumerUpdated(initialOwner, true);
    }

    function registerAdapter(bytes32 adapterId, address adapter) external onlyOwner {
        if (adapterId == bytes32(0)) revert InvalidAdapterId();
        if (adapter == address(0) || adapter.code.length == 0) revert InvalidAdapter();
        adapters[adapterId] = adapter;
        emit AdapterRegistered(adapterId, adapter);
    }

    function setAuthorizedConsumer(address consumer, bool allowed) external onlyOwner {
        authorizedConsumers[consumer] = allowed;
        emit AuthorizedConsumerUpdated(consumer, allowed);
    }

    function setEpoch(uint64 newEpoch) external onlyOwner {
        if (newEpoch <= currentEpoch) revert InvalidEpoch();
        uint64 oldEpoch = currentEpoch;
        currentEpoch = newEpoch;
        emit EpochUpdated(oldEpoch, newEpoch);
    }

    function createPolicy(
        SatisfyTypes.LogicOp logic,
        SatisfyTypes.Predicate[] calldata predicates,
        uint64 startTime,
        uint64 endTime,
        bool active
    ) external onlyOwner returns (uint256 policyId) {
        if (predicates.length == 0) revert EmptyPolicy();
        if (endTime != 0 && endTime <= startTime) revert InvalidPolicyWindow();

        policyId = ++policyCount;
        Policy storage policy = policies[policyId];
        policy.logic = logic;
        policy.startTime = startTime;
        policy.endTime = endTime;
        policy.active = active;

        for (uint256 i = 0; i < predicates.length; ++i) {
            if (predicates[i].adapterId == bytes32(0)) revert InvalidAdapterId();
            policy.predicates.push(predicates[i]);
        }

        emit PolicyCreated(policyId, logic, startTime, endTime, active, predicates.length);
    }

    function setPolicyActive(uint256 policyId, bool active) external onlyOwner {
        Policy storage policy = policies[policyId];
        if (policy.predicates.length == 0) revert PolicyDoesNotExist(policyId);
        policy.active = active;
        emit PolicyActiveUpdated(policyId, active);
    }

    function setPolicyWindow(uint256 policyId, uint64 startTime, uint64 endTime) external onlyOwner {
        if (endTime != 0 && endTime <= startTime) revert InvalidPolicyWindow();
        Policy storage policy = policies[policyId];
        if (policy.predicates.length == 0) revert PolicyDoesNotExist(policyId);

        policy.startTime = startTime;
        policy.endTime = endTime;
        emit PolicyWindowUpdated(policyId, startTime, endTime);
    }

    function getPolicyMeta(uint256 policyId)
        external
        view
        returns (SatisfyTypes.LogicOp logic, uint64 startTime, uint64 endTime, bool active, uint256 predicateCount)
    {
        Policy storage policy = policies[policyId];
        if (policy.predicates.length == 0) revert PolicyDoesNotExist(policyId);
        return (policy.logic, policy.startTime, policy.endTime, policy.active, policy.predicates.length);
    }

    function getPredicate(uint256 policyId, uint256 predicateIndex)
        external
        view
        returns (bytes32 adapterId, bytes memory condition)
    {
        Policy storage policy = policies[policyId];
        if (policy.predicates.length == 0) revert PolicyDoesNotExist(policyId);
        SatisfyTypes.Predicate storage predicate = policy.predicates[predicateIndex];
        return (predicate.adapterId, predicate.condition);
    }

    function isPolicyActive(uint256 policyId) public view returns (bool) {
        Policy storage policy = policies[policyId];
        if (policy.predicates.length == 0) return false;
        return _isPolicyActive(policy);
    }

    function satisfies(uint256 policyId, address user, SatisfyTypes.ProofBundle calldata bundle)
        external
        view
        override
        returns (bool)
    {
        return _satisfies(policyId, user, bundle);
    }

    function validateAndConsume(uint256 policyId, address user, SatisfyTypes.ProofBundle calldata bundle)
        external
        override
        onlyAuthorizedConsumer
        returns (bool)
    {
        Policy storage policy = policies[policyId];
        if (policy.predicates.length == 0) revert PolicyDoesNotExist(policyId);
        if (!_isPolicyActive(policy)) revert PolicyInactive(policyId);
        if (bundle.epoch != currentEpoch) revert InvalidEpoch();

        bytes32 replayKey = _replayKey(policyId, user, bundle.epoch, bundle.nullifier);
        if (nullifierUsed[replayKey]) revert NullifierAlreadyUsed(replayKey);

        if (!_evaluatePolicy(policy, user, bundle.proofs)) revert PolicyCheckFailed(policyId);

        nullifierUsed[replayKey] = true;
        emit ProofConsumed(policyId, user, replayKey, bundle.nullifier);
        return true;
    }

    function _satisfies(uint256 policyId, address user, SatisfyTypes.ProofBundle calldata bundle)
        internal
        view
        returns (bool)
    {
        Policy storage policy = policies[policyId];
        if (policy.predicates.length == 0) return false;
        if (!_isPolicyActive(policy)) return false;
        if (bundle.epoch != currentEpoch) return false;
        return _evaluatePolicy(policy, user, bundle.proofs);
    }

    function _evaluatePolicy(Policy storage policy, address user, SatisfyTypes.Proof[] calldata proofs)
        internal
        view
        returns (bool)
    {
        if (policy.logic == SatisfyTypes.LogicOp.AND) {
            for (uint256 i = 0; i < policy.predicates.length; ++i) {
                if (!_predicateSatisfied(policy.predicates[i], user, proofs)) {
                    return false;
                }
            }
            return true;
        }

        for (uint256 i = 0; i < policy.predicates.length; ++i) {
            if (_predicateSatisfied(policy.predicates[i], user, proofs)) {
                return true;
            }
        }
        return false;
    }

    function _predicateSatisfied(
        SatisfyTypes.Predicate storage predicate,
        address user,
        SatisfyTypes.Proof[] calldata proofs
    ) internal view returns (bool) {
        address adapter = adapters[predicate.adapterId];
        if (adapter == address(0)) return false;

        (bool foundProof, uint256 proofIndex) = _findProof(predicate.adapterId, proofs);
        if (!foundProof) return false;

        try ICredentialAdapter(adapter).verify(user, proofs[proofIndex].payload, predicate.condition) returns (
            bool ok
        ) {
            return ok;
        } catch {
            return false;
        }
    }

    function _findProof(bytes32 adapterId, SatisfyTypes.Proof[] calldata proofs)
        internal
        pure
        returns (bool found, uint256 index)
    {
        for (uint256 i = 0; i < proofs.length; ++i) {
            if (proofs[i].adapterId == adapterId) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function _isPolicyActive(Policy storage policy) internal view returns (bool) {
        if (!policy.active) return false;
        if (policy.startTime != 0 && block.timestamp < policy.startTime) return false;
        if (policy.endTime != 0 && block.timestamp > policy.endTime) return false;
        return true;
    }

    function _replayKey(uint256 policyId, address user, uint64 epoch, bytes32 nullifier)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(policyId, user, epoch, nullifier));
    }
}
