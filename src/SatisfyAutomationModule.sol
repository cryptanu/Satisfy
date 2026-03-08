// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {SatisfyTypes} from "./types/SatisfyTypes.sol";

interface IAutomationPolicyEngine {
    function registerAdapter(bytes32 adapterId, address adapter) external;
    function setAuthorizedConsumer(address consumer, bool allowed) external;
    function setEpoch(uint64 newEpoch) external;
    function createPolicy(
        SatisfyTypes.LogicOp logic,
        SatisfyTypes.Predicate[] calldata predicates,
        uint64 startTime,
        uint64 endTime,
        bool active
    ) external returns (uint256 policyId);
    function setPolicyActive(uint256 policyId, bool active) external;
    function setPolicyWindow(uint256 policyId, uint64 startTime, uint64 endTime) external;
    function setPaused(bool paused) external;
}

interface IAutomationHook {
    function setPoolPolicy(bytes32 poolId, uint256 policyId) external;
    function setHookCaller(address caller, bool allowed) external;
    function setPaused(bool paused) external;
}

interface IAutomationWorldAdapter {
    function setVerifier(address newVerifier, uint256 newGroupId) external;
}

interface IAutomationSelfAdapter {
    function setRegistry(address newRegistry) external;
}

interface IAutomationSelfRegistry {
    function setTrustedSigner(address signer, bool allowed) external;
    function revokeAttestation(bytes32 attestationId) external;
}

contract SatisfyAutomationModule is Ownable {
    bytes32 public constant POLICY_MANAGER_ROLE = keccak256("POLICY_MANAGER_ROLE");
    bytes32 public constant ADAPTER_MANAGER_ROLE = keccak256("ADAPTER_MANAGER_ROLE");
    bytes32 public constant HOOK_MANAGER_ROLE = keccak256("HOOK_MANAGER_ROLE");
    bytes32 public constant REACTIVE_EXECUTOR_ROLE = keccak256("REACTIVE_EXECUTOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    IAutomationPolicyEngine public immutable policyEngine;
    IAutomationHook public immutable hook;
    IAutomationWorldAdapter public immutable worldAdapter;
    IAutomationSelfAdapter public immutable selfAdapter;
    IAutomationSelfRegistry public immutable selfRegistry;

    address public roleAdmin;

    mapping(bytes32 => mapping(address => bool)) public hasRole;
    mapping(bytes32 => bool) public executedJob;

    error InvalidAddress();
    error InvalidJobId();
    error JobAlreadyExecuted(bytes32 jobId);
    error NotRoleAdmin();
    error MissingRole(bytes32 role, address account);

    event JobExecuted(bytes32 indexed jobId, bytes4 indexed actionSelector, address indexed executor);
    event RoleAdminUpdated(address indexed previousRoleAdmin, address indexed newRoleAdmin);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    modifier onlyRoleAdmin() {
        if (msg.sender != roleAdmin) revert NotRoleAdmin();
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!hasRole[role][msg.sender]) revert MissingRole(role, msg.sender);
        _;
    }

    constructor(
        address initialOwner,
        address initialRoleAdmin,
        address policyManager,
        address adapterManager,
        address hookManager,
        address reactiveExecutor,
        address emergencyActor,
        address policyEngineAddress,
        address hookAddress,
        address worldAdapterAddress,
        address selfAdapterAddress,
        address selfRegistryAddress
    ) Ownable(initialOwner) {
        if (
            initialRoleAdmin == address(0) || policyManager == address(0) || adapterManager == address(0)
                || hookManager == address(0) || reactiveExecutor == address(0) || emergencyActor == address(0)
                || policyEngineAddress == address(0) || hookAddress == address(0) || worldAdapterAddress == address(0)
                || selfAdapterAddress == address(0) || selfRegistryAddress == address(0)
        ) revert InvalidAddress();

        roleAdmin = initialRoleAdmin;
        emit RoleAdminUpdated(address(0), initialRoleAdmin);

        policyEngine = IAutomationPolicyEngine(policyEngineAddress);
        hook = IAutomationHook(hookAddress);
        worldAdapter = IAutomationWorldAdapter(worldAdapterAddress);
        selfAdapter = IAutomationSelfAdapter(selfAdapterAddress);
        selfRegistry = IAutomationSelfRegistry(selfRegistryAddress);

        _grantRole(POLICY_MANAGER_ROLE, policyManager);
        _grantRole(ADAPTER_MANAGER_ROLE, adapterManager);
        _grantRole(HOOK_MANAGER_ROLE, hookManager);
        _grantRole(REACTIVE_EXECUTOR_ROLE, reactiveExecutor);
        _grantRole(EMERGENCY_ROLE, emergencyActor);
    }

    function setRoleAdmin(address newRoleAdmin) external onlyRoleAdmin {
        if (newRoleAdmin == address(0)) revert InvalidAddress();
        address oldRoleAdmin = roleAdmin;
        roleAdmin = newRoleAdmin;
        emit RoleAdminUpdated(oldRoleAdmin, newRoleAdmin);
    }

    function grantRole(bytes32 role, address account) external onlyRoleAdmin {
        if (account == address(0)) revert InvalidAddress();
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRoleAdmin {
        if (!hasRole[role][account]) return;
        hasRole[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function registerAdapter(bytes32 adapterId, address adapter) external onlyRole(ADAPTER_MANAGER_ROLE) {
        policyEngine.registerAdapter(adapterId, adapter);
    }

    function setAuthorizedConsumer(address consumer, bool allowed) external onlyRole(HOOK_MANAGER_ROLE) {
        policyEngine.setAuthorizedConsumer(consumer, allowed);
    }

    function createPolicy(
        SatisfyTypes.LogicOp logic,
        SatisfyTypes.Predicate[] calldata predicates,
        uint64 startTime,
        uint64 endTime,
        bool active
    ) external onlyRole(POLICY_MANAGER_ROLE) returns (uint256 policyId) {
        return policyEngine.createPolicy(logic, predicates, startTime, endTime, active);
    }

    function setEpoch(uint64 newEpoch) external onlyRole(POLICY_MANAGER_ROLE) {
        policyEngine.setEpoch(newEpoch);
    }

    function setPolicyActive(uint256 policyId, bool active) external onlyRole(POLICY_MANAGER_ROLE) {
        policyEngine.setPolicyActive(policyId, active);
    }

    function setPolicyWindow(uint256 policyId, uint64 startTime, uint64 endTime) external onlyRole(POLICY_MANAGER_ROLE) {
        policyEngine.setPolicyWindow(policyId, startTime, endTime);
    }

    function setPoolPolicy(bytes32 poolId, uint256 policyId) external onlyRole(HOOK_MANAGER_ROLE) {
        hook.setPoolPolicy(poolId, policyId);
    }

    function setHookCaller(address caller, bool allowed) external onlyRole(HOOK_MANAGER_ROLE) {
        hook.setHookCaller(caller, allowed);
    }

    function setWorldVerifier(address newVerifier, uint256 newGroupId) external onlyRole(ADAPTER_MANAGER_ROLE) {
        worldAdapter.setVerifier(newVerifier, newGroupId);
    }

    function setSelfRegistry(address newRegistry) external onlyRole(ADAPTER_MANAGER_ROLE) {
        selfAdapter.setRegistry(newRegistry);
    }

    function setSelfTrustedSigner(address signer, bool allowed) external onlyRole(ADAPTER_MANAGER_ROLE) {
        selfRegistry.setTrustedSigner(signer, allowed);
    }

    function revokeSelfAttestation(bytes32 attestationId) external onlyRole(ADAPTER_MANAGER_ROLE) {
        selfRegistry.revokeAttestation(attestationId);
    }

    function pauseAll(bool paused) external onlyRole(EMERGENCY_ROLE) {
        policyEngine.setPaused(paused);
        hook.setPaused(paused);
    }

    function reactiveSetEpoch(bytes32 jobId, uint64 newEpoch) external onlyRole(REACTIVE_EXECUTOR_ROLE) {
        _consumeJob(jobId, this.reactiveSetEpoch.selector);
        policyEngine.setEpoch(newEpoch);
    }

    function reactiveSetPolicyActive(bytes32 jobId, uint256 policyId, bool active)
        external
        onlyRole(REACTIVE_EXECUTOR_ROLE)
    {
        _consumeJob(jobId, this.reactiveSetPolicyActive.selector);
        policyEngine.setPolicyActive(policyId, active);
    }

    function reactiveSetPolicyWindow(bytes32 jobId, uint256 policyId, uint64 startTime, uint64 endTime)
        external
        onlyRole(REACTIVE_EXECUTOR_ROLE)
    {
        _consumeJob(jobId, this.reactiveSetPolicyWindow.selector);
        policyEngine.setPolicyWindow(policyId, startTime, endTime);
    }

    function reactiveSetPoolPolicy(bytes32 jobId, bytes32 poolId, uint256 policyId)
        external
        onlyRole(REACTIVE_EXECUTOR_ROLE)
    {
        _consumeJob(jobId, this.reactiveSetPoolPolicy.selector);
        hook.setPoolPolicy(poolId, policyId);
    }

    function reactiveSetHookCaller(bytes32 jobId, address caller, bool allowed)
        external
        onlyRole(REACTIVE_EXECUTOR_ROLE)
    {
        _consumeJob(jobId, this.reactiveSetHookCaller.selector);
        hook.setHookCaller(caller, allowed);
    }

    function reactiveSetWorldVerifier(bytes32 jobId, address newVerifier, uint256 newGroupId)
        external
        onlyRole(REACTIVE_EXECUTOR_ROLE)
    {
        _consumeJob(jobId, this.reactiveSetWorldVerifier.selector);
        worldAdapter.setVerifier(newVerifier, newGroupId);
    }

    function reactiveSetSelfRegistry(bytes32 jobId, address newRegistry) external onlyRole(REACTIVE_EXECUTOR_ROLE) {
        _consumeJob(jobId, this.reactiveSetSelfRegistry.selector);
        selfAdapter.setRegistry(newRegistry);
    }

    function reactiveSetSelfTrustedSigner(bytes32 jobId, address signer, bool allowed)
        external
        onlyRole(REACTIVE_EXECUTOR_ROLE)
    {
        _consumeJob(jobId, this.reactiveSetSelfTrustedSigner.selector);
        selfRegistry.setTrustedSigner(signer, allowed);
    }

    function reactivePauseAll(bytes32 jobId, bool paused) external onlyRole(REACTIVE_EXECUTOR_ROLE) {
        _consumeJob(jobId, this.reactivePauseAll.selector);
        policyEngine.setPaused(paused);
        hook.setPaused(paused);
    }

    function _consumeJob(bytes32 jobId, bytes4 actionSelector) internal {
        if (jobId == bytes32(0)) revert InvalidJobId();
        if (executedJob[jobId]) revert JobAlreadyExecuted(jobId);
        executedJob[jobId] = true;
        emit JobExecuted(jobId, actionSelector, msg.sender);
    }

    function _grantRole(bytes32 role, address account) internal {
        if (hasRole[role][account]) return;
        hasRole[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }
}
