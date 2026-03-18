// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "./interfaces/ICredentialAdapter.sol";
import {ICredentialAdapterV2} from "./interfaces/ICredentialAdapterV2.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {SatisfyTypes} from "./types/SatisfyTypes.sol";
import {Ownable} from "./utils/Ownable.sol";

contract SatisfyPolicyEngine is IPolicyEngine, Ownable {
    struct EvaluationContext {
        uint256 policyId;
        bytes32 bundleNullifier;
        uint64 epoch;
    }

    struct Policy {
        SatisfyTypes.LogicOp logic;
        uint64 startTime;
        uint64 endTime;
        bool active;
        bool useGroups;
        SatisfyTypes.Predicate[] predicates;
    }

    mapping(bytes32 => address) public adapters;
    mapping(uint256 => Policy) private policies;
    mapping(uint256 => uint256) private policyGroupCount;
    mapping(uint256 => mapping(uint256 => SatisfyTypes.Predicate[])) private policyGroupPredicates;
    mapping(address => bool) public authorizedConsumers;
    mapping(bytes32 => bool) public nullifierUsed;

    uint256 public policyCount;
    uint64 public currentEpoch;
    bool public paused;

    error EmptyPolicy();
    error InvalidAdapter();
    error InvalidAdapterId();
    error InvalidEpoch();
    error InvalidPolicyWindow();
    error NotAuthorizedConsumer();
    error NullifierAlreadyUsed(bytes32 replayKey);
    error EmptyPredicateGroup(uint256 groupIndex);
    error PolicyNotGroupBased(uint256 policyId);
    error PolicyUsesGroups(uint256 policyId);
    error PredicateGroupDoesNotExist(uint256 policyId, uint256 groupIndex);
    error PolicyEnginePaused();
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
    event PolicyV2Created(
        uint256 indexed policyId,
        uint64 startTime,
        uint64 endTime,
        bool active,
        uint256 groupCount,
        uint256 predicateCount
    );
    event PolicyWindowUpdated(uint256 indexed policyId, uint64 startTime, uint64 endTime);
    event ProofConsumed(uint256 indexed policyId, address indexed user, bytes32 indexed replayKey, bytes32 nullifier);
    event PauseUpdated(bool paused);

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

    function setPaused(bool nextPaused) external onlyOwner {
        paused = nextPaused;
        emit PauseUpdated(nextPaused);
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
        policy.useGroups = false;

        for (uint256 i = 0; i < predicates.length; ++i) {
            if (predicates[i].adapterId == bytes32(0)) revert InvalidAdapterId();
            policy.predicates.push(predicates[i]);
        }

        emit PolicyCreated(policyId, logic, startTime, endTime, active, predicates.length);
    }

    function createPolicyV2(SatisfyTypes.PredicateGroup[] calldata groups, uint64 startTime, uint64 endTime, bool active)
        external
        onlyOwner
        returns (uint256 policyId)
    {
        if (groups.length == 0) revert EmptyPolicy();
        if (endTime != 0 && endTime <= startTime) revert InvalidPolicyWindow();

        uint256 totalPredicates = 0;
        policyId = ++policyCount;

        Policy storage policy = policies[policyId];
        policy.logic = SatisfyTypes.LogicOp.OR;
        policy.startTime = startTime;
        policy.endTime = endTime;
        policy.active = active;
        policy.useGroups = true;

        for (uint256 groupIndex = 0; groupIndex < groups.length; ++groupIndex) {
            SatisfyTypes.Predicate[] calldata predicates = groups[groupIndex].predicates;
            if (predicates.length == 0) revert EmptyPredicateGroup(groupIndex);

            for (uint256 predicateIndex = 0; predicateIndex < predicates.length; ++predicateIndex) {
                if (predicates[predicateIndex].adapterId == bytes32(0)) revert InvalidAdapterId();
                policyGroupPredicates[policyId][groupIndex].push(predicates[predicateIndex]);
                ++totalPredicates;
            }
        }

        policyGroupCount[policyId] = groups.length;
        emit PolicyV2Created(policyId, startTime, endTime, active, groups.length, totalPredicates);
    }

    function setPolicyActive(uint256 policyId, bool active) external onlyOwner {
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) revert PolicyDoesNotExist(policyId);
        policy.active = active;
        emit PolicyActiveUpdated(policyId, active);
    }

    function setPolicyWindow(uint256 policyId, uint64 startTime, uint64 endTime) external onlyOwner {
        if (endTime != 0 && endTime <= startTime) revert InvalidPolicyWindow();
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) revert PolicyDoesNotExist(policyId);

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
        if (!_policyExists(policyId, policy)) revert PolicyDoesNotExist(policyId);
        return (policy.logic, policy.startTime, policy.endTime, policy.active, _policyPredicateCount(policyId, policy));
    }

    function getPredicate(uint256 policyId, uint256 predicateIndex)
        external
        view
        returns (bytes32 adapterId, bytes memory condition)
    {
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) revert PolicyDoesNotExist(policyId);
        if (policy.useGroups) revert PolicyUsesGroups(policyId);
        SatisfyTypes.Predicate storage predicate = policy.predicates[predicateIndex];
        return (predicate.adapterId, predicate.condition);
    }

    function getPolicyGroupCount(uint256 policyId) external view returns (uint256) {
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) revert PolicyDoesNotExist(policyId);
        if (!policy.useGroups) revert PolicyNotGroupBased(policyId);
        return policyGroupCount[policyId];
    }

    function getPolicyGroupPredicateCount(uint256 policyId, uint256 groupIndex) external view returns (uint256) {
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) revert PolicyDoesNotExist(policyId);
        if (!policy.useGroups) revert PolicyNotGroupBased(policyId);
        uint256 groupCount = policyGroupCount[policyId];
        if (groupIndex >= groupCount) revert PredicateGroupDoesNotExist(policyId, groupIndex);
        return policyGroupPredicates[policyId][groupIndex].length;
    }

    function getPolicyGroupPredicate(uint256 policyId, uint256 groupIndex, uint256 predicateIndex)
        external
        view
        returns (bytes32 adapterId, bytes memory condition)
    {
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) revert PolicyDoesNotExist(policyId);
        if (!policy.useGroups) revert PolicyNotGroupBased(policyId);
        uint256 groupCount = policyGroupCount[policyId];
        if (groupIndex >= groupCount) revert PredicateGroupDoesNotExist(policyId, groupIndex);
        SatisfyTypes.Predicate storage predicate = policyGroupPredicates[policyId][groupIndex][predicateIndex];
        return (predicate.adapterId, predicate.condition);
    }

    function isPolicyActive(uint256 policyId) public view returns (bool) {
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) return false;
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
        if (paused) revert PolicyEnginePaused();
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) revert PolicyDoesNotExist(policyId);
        if (!_isPolicyActive(policy)) revert PolicyInactive(policyId);
        if (bundle.epoch != currentEpoch) revert InvalidEpoch();

        bytes32 replayKey = _replayKey(policyId, user, bundle.epoch, bundle.nullifier);
        if (nullifierUsed[replayKey]) revert NullifierAlreadyUsed(replayKey);

        if (!_evaluatePolicy(policyId, policy, user, bundle.proofs, bundle.nullifier, bundle.epoch)) {
            revert PolicyCheckFailed(policyId);
        }

        nullifierUsed[replayKey] = true;
        emit ProofConsumed(policyId, user, replayKey, bundle.nullifier);
        return true;
    }

    function _satisfies(uint256 policyId, address user, SatisfyTypes.ProofBundle calldata bundle)
        internal
        view
        returns (bool)
    {
        if (paused) return false;
        Policy storage policy = policies[policyId];
        if (!_policyExists(policyId, policy)) return false;
        if (!_isPolicyActive(policy)) return false;
        if (bundle.epoch != currentEpoch) return false;
        return _evaluatePolicy(policyId, policy, user, bundle.proofs, bundle.nullifier, bundle.epoch);
    }

    function _evaluatePolicy(
        uint256 policyId,
        Policy storage policy,
        address user,
        SatisfyTypes.Proof[] calldata proofs,
        bytes32 bundleNullifier,
        uint64 epoch
    )
        internal
        view
        returns (bool)
    {
        EvaluationContext memory ctx =
            EvaluationContext({policyId: policyId, bundleNullifier: bundleNullifier, epoch: epoch});

        if (policy.useGroups) {
            uint256 groupCount = policyGroupCount[policyId];
            for (uint256 i = 0; i < groupCount; ++i) {
                if (_evaluatePredicateGroup(policyId, i, user, proofs, ctx)) {
                    return true;
                }
            }
            return false;
        }

        if (policy.logic == SatisfyTypes.LogicOp.AND) {
            for (uint256 i = 0; i < policy.predicates.length; ++i) {
                if (!_predicateSatisfied(policy.predicates[i], user, proofs, ctx)) {
                    return false;
                }
            }
            return true;
        }

        for (uint256 i = 0; i < policy.predicates.length; ++i) {
            if (_predicateSatisfied(policy.predicates[i], user, proofs, ctx)) {
                return true;
            }
        }
        return false;
    }

    function _evaluatePredicateGroup(
        uint256 policyId,
        uint256 groupIndex,
        address user,
        SatisfyTypes.Proof[] calldata proofs,
        EvaluationContext memory ctx
    ) internal view returns (bool) {
        SatisfyTypes.Predicate[] storage predicates = policyGroupPredicates[policyId][groupIndex];
        for (uint256 i = 0; i < predicates.length; ++i) {
            if (!_predicateSatisfied(predicates[i], user, proofs, ctx)) {
                return false;
            }
        }
        return true;
    }

    function _predicateSatisfied(
        SatisfyTypes.Predicate storage predicate,
        address user,
        SatisfyTypes.Proof[] calldata proofs,
        EvaluationContext memory ctx
    ) internal view returns (bool) {
        address adapter = adapters[predicate.adapterId];
        if (adapter == address(0)) return false;

        (bool foundProof, uint256 proofIndex) = _findProof(predicate.adapterId, proofs);
        if (!foundProof) return false;

        bytes calldata payload = proofs[proofIndex].payload;
        bytes memory condition = predicate.condition;

        (bool handled, bool contextOk) = _verifyWithContextFromCtx(adapter, user, payload, condition, ctx);
        if (handled) return contextOk;

        try ICredentialAdapter(adapter).verify(user, payload, condition) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function _verifyWithContextFromCtx(
        address adapter,
        address user,
        bytes calldata proofPayload,
        bytes memory policyCondition,
        EvaluationContext memory ctx
    ) internal view returns (bool handled, bool ok) {
        return _verifyWithContext(
            adapter, user, proofPayload, policyCondition, ctx.bundleNullifier, ctx.epoch, ctx.policyId
        );
    }

    function _verifyWithContext(
        address adapter,
        address user,
        bytes calldata proofPayload,
        bytes memory policyCondition,
        bytes32 bundleNullifier,
        uint64 epoch,
        uint256 policyId
    ) internal view returns (bool handled, bool ok) {
        try ICredentialAdapterV2(adapter).verifyWithContext(
            user, proofPayload, policyCondition, bundleNullifier, epoch, policyId
        ) returns (bool contextOk) {
            return (true, contextOk);
        } catch {
            return (false, false);
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

    function _policyExists(uint256 policyId, Policy storage policy) internal view returns (bool) {
        if (policy.useGroups) {
            return policyGroupCount[policyId] != 0;
        }
        return policy.predicates.length != 0;
    }

    function _policyPredicateCount(uint256 policyId, Policy storage policy) internal view returns (uint256 count) {
        if (!policy.useGroups) {
            return policy.predicates.length;
        }

        uint256 groupCount = policyGroupCount[policyId];
        for (uint256 i = 0; i < groupCount; ++i) {
            count += policyGroupPredicates[policyId][i].length;
        }
    }

    function _replayKey(uint256 policyId, address user, uint64 epoch, bytes32 nullifier)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(policyId, user, epoch, nullifier));
    }
}
