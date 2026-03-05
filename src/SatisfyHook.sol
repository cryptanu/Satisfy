// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {SatisfyTypes} from "./types/SatisfyTypes.sol";
import {Ownable} from "./utils/Ownable.sol";

contract SatisfyHook is Ownable {
    IPolicyEngine public immutable policyEngine;

    mapping(bytes32 => uint256) public poolPolicy;
    mapping(address => bool) public authorizedCallers;

    error HookCallerNotAuthorized();
    error PoolPolicyNotSet(bytes32 poolId);

    event HookCallerUpdated(address indexed caller, bool allowed);
    event PoolPolicyUpdated(bytes32 indexed poolId, uint256 indexed policyId);
    event PolicyConsumed(bytes32 indexed poolId, address indexed user, uint256 indexed policyId, bytes4 hookSelector);

    modifier onlyAuthorizedCaller() {
        if (!authorizedCallers[msg.sender]) revert HookCallerNotAuthorized();
        _;
    }

    constructor(address initialOwner, address policyEngineAddress, address initialHookCaller) Ownable(initialOwner) {
        policyEngine = IPolicyEngine(policyEngineAddress);
        authorizedCallers[initialOwner] = true;
        emit HookCallerUpdated(initialOwner, true);

        if (initialHookCaller != address(0)) {
            authorizedCallers[initialHookCaller] = true;
            emit HookCallerUpdated(initialHookCaller, true);
        }
    }

    function setHookCaller(address caller, bool allowed) external onlyOwner {
        authorizedCallers[caller] = allowed;
        emit HookCallerUpdated(caller, allowed);
    }

    function setPoolPolicy(bytes32 poolId, uint256 policyId) external onlyOwner {
        poolPolicy[poolId] = policyId;
        emit PoolPolicyUpdated(poolId, policyId);
    }

    function beforeSwap(bytes32 poolId, address sender, SatisfyTypes.ProofBundle calldata bundle)
        external
        onlyAuthorizedCaller
        returns (bytes4)
    {
        _enforce(poolId, sender, bundle, this.beforeSwap.selector);
        return this.beforeSwap.selector;
    }

    function beforeAddLiquidity(bytes32 poolId, address sender, SatisfyTypes.ProofBundle calldata bundle)
        external
        onlyAuthorizedCaller
        returns (bytes4)
    {
        _enforce(poolId, sender, bundle, this.beforeAddLiquidity.selector);
        return this.beforeAddLiquidity.selector;
    }

    function _enforce(bytes32 poolId, address sender, SatisfyTypes.ProofBundle calldata bundle, bytes4 selector)
        internal
    {
        uint256 policyId = poolPolicy[poolId];
        if (policyId == 0) revert PoolPolicyNotSet(poolId);

        policyEngine.validateAndConsume(policyId, sender, bundle);
        emit PolicyConsumed(poolId, sender, policyId, selector);
    }
}
