// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ECDSA} from "./utils/ECDSA.sol";

interface IReactiveAutomationModule {
    function reactiveSetEpoch(bytes32 jobId, uint64 newEpoch) external;
    function reactiveSetPolicyActive(bytes32 jobId, uint256 policyId, bool active) external;
    function reactiveSetPolicyWindow(bytes32 jobId, uint256 policyId, uint64 startTime, uint64 endTime) external;
    function reactiveSetPoolPolicy(bytes32 jobId, bytes32 poolId, uint256 policyId) external;
    function reactiveSetHookCaller(bytes32 jobId, address caller, bool allowed) external;
    function reactiveSetWorldVerifier(bytes32 jobId, address newVerifier, uint256 newGroupId) external;
    function reactiveSetSelfRegistry(bytes32 jobId, address newRegistry) external;
    function reactiveSetSelfTrustedSigner(bytes32 jobId, address signer, bool allowed) external;
    function reactivePauseAll(bytes32 jobId, bool paused) external;
}

contract SatisfyReactiveGateway is Ownable {
    using ECDSA for bytes32;

    struct JobV1 {
        bytes32 jobId;
        uint8 action;
        bytes payload;
        uint64 validUntil;
        uint256 nonce;
    }

    uint8 public constant ACTION_SET_EPOCH = 0;
    uint8 public constant ACTION_SET_POLICY_ACTIVE = 1;
    uint8 public constant ACTION_SET_POLICY_WINDOW = 2;
    uint8 public constant ACTION_SET_POOL_POLICY = 3;
    uint8 public constant ACTION_SET_HOOK_CALLER = 4;
    uint8 public constant ACTION_SET_WORLD_VERIFIER = 5;
    uint8 public constant ACTION_SET_SELF_REGISTRY = 6;
    uint8 public constant ACTION_SET_SELF_TRUSTED_SIGNER = 7;
    uint8 public constant ACTION_PAUSE_ALL = 8;

    bytes32 public constant JOB_TYPEHASH =
        keccak256("JobV1(bytes32 jobId,uint8 action,bytes32 payloadHash,uint64 validUntil,uint256 nonce)");

    address public automationModule;
    mapping(address => bool) public trustedWorkers;
    mapping(address => bool) public authorizedReactiveCallbacks;
    mapping(address => uint256) public nextNonce;
    mapping(bytes32 => bool) public consumedDigest;

    error InvalidAddress();
    error InvalidJobId();
    error AutomationNotSet();
    error InvalidWorker(address worker);
    error UnauthorizedReactiveCallback(address callback);
    error InvalidNonce(uint256 expected, uint256 actual);
    error SignatureExpired(uint64 validUntil, uint64 nowTs);
    error DigestAlreadyConsumed(bytes32 digest);
    error InvalidAction(uint8 action);

    event AutomationModuleUpdated(address indexed previousAutomation, address indexed newAutomation);
    event TrustedWorkerUpdated(address indexed worker, bool allowed);
    event ReactiveCallbackUpdated(address indexed callback, bool allowed);
    event JobExecuted(bytes32 indexed jobId, uint8 indexed action, address indexed worker, address relayer);

    constructor(address initialOwner, address initialAutomationModule, address initialWorker) Ownable(initialOwner) {
        if (initialWorker == address(0)) revert InvalidAddress();
        trustedWorkers[initialWorker] = true;
        emit TrustedWorkerUpdated(initialWorker, true);

        if (initialAutomationModule != address(0)) {
            automationModule = initialAutomationModule;
            emit AutomationModuleUpdated(address(0), initialAutomationModule);
        }
    }

    function setAutomationModule(address newAutomationModule) external onlyOwner {
        if (newAutomationModule == address(0)) revert InvalidAddress();
        address oldAutomationModule = automationModule;
        automationModule = newAutomationModule;
        emit AutomationModuleUpdated(oldAutomationModule, newAutomationModule);
    }

    function setTrustedWorker(address worker, bool allowed) external onlyOwner {
        if (worker == address(0)) revert InvalidAddress();
        trustedWorkers[worker] = allowed;
        emit TrustedWorkerUpdated(worker, allowed);
    }

    function setReactiveCallback(address callbackContract, bool allowed) external onlyOwner {
        if (callbackContract == address(0)) revert InvalidAddress();
        authorizedReactiveCallbacks[callbackContract] = allowed;
        emit ReactiveCallbackUpdated(callbackContract, allowed);
    }

    function jobDigest(JobV1 calldata job) public view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(JOB_TYPEHASH, job.jobId, job.action, keccak256(job.payload), job.validUntil, job.nonce));
        return keccak256(
            abi.encodePacked("SATISFY_REACTIVE_GATEWAY_V1", block.chainid, address(this), automationModule, structHash)
        ).toEthSignedMessageHash();
    }

    function execute(JobV1 calldata job, bytes calldata signature) external {
        if (automationModule == address(0)) revert AutomationNotSet();
        if (job.jobId == bytes32(0)) revert InvalidJobId();
        if (job.validUntil != 0 && block.timestamp > job.validUntil) {
            revert SignatureExpired(job.validUntil, uint64(block.timestamp));
        }

        bytes32 digest = jobDigest(job);
        if (consumedDigest[digest]) revert DigestAlreadyConsumed(digest);

        address worker = digest.recover(signature);
        if (!trustedWorkers[worker]) revert InvalidWorker(worker);

        uint256 expectedNonce = nextNonce[worker];
        if (job.nonce != expectedNonce) revert InvalidNonce(expectedNonce, job.nonce);

        nextNonce[worker] = expectedNonce + 1;
        consumedDigest[digest] = true;

        _dispatch(job.jobId, job.action, job.payload);
        emit JobExecuted(job.jobId, job.action, worker, msg.sender);
    }

    function executeFromReactiveCallback(bytes32 jobId, uint8 action, bytes calldata payload) external {
        if (automationModule == address(0)) revert AutomationNotSet();
        if (jobId == bytes32(0)) revert InvalidJobId();
        if (!authorizedReactiveCallbacks[msg.sender]) revert UnauthorizedReactiveCallback(msg.sender);

        bytes32 replayDigest = keccak256(
            abi.encodePacked(
                "SATISFY_REACTIVE_CALLBACK_V1", block.chainid, address(this), msg.sender, jobId, action, keccak256(payload)
            )
        );
        if (consumedDigest[replayDigest]) revert DigestAlreadyConsumed(replayDigest);
        consumedDigest[replayDigest] = true;

        _dispatch(jobId, action, payload);
        emit JobExecuted(jobId, action, msg.sender, msg.sender);
    }

    function _dispatch(bytes32 jobId, uint8 action, bytes calldata payload) internal {
        IReactiveAutomationModule automation = IReactiveAutomationModule(automationModule);

        if (action == ACTION_SET_EPOCH) {
            automation.reactiveSetEpoch(jobId, abi.decode(payload, (uint64)));
            return;
        }
        if (action == ACTION_SET_POLICY_ACTIVE) {
            (uint256 policyId, bool active) = abi.decode(payload, (uint256, bool));
            automation.reactiveSetPolicyActive(jobId, policyId, active);
            return;
        }
        if (action == ACTION_SET_POLICY_WINDOW) {
            (uint256 policyId, uint64 startTime, uint64 endTime) = abi.decode(payload, (uint256, uint64, uint64));
            automation.reactiveSetPolicyWindow(jobId, policyId, startTime, endTime);
            return;
        }
        if (action == ACTION_SET_POOL_POLICY) {
            (bytes32 poolId, uint256 policyId) = abi.decode(payload, (bytes32, uint256));
            automation.reactiveSetPoolPolicy(jobId, poolId, policyId);
            return;
        }
        if (action == ACTION_SET_HOOK_CALLER) {
            (address caller, bool allowed) = abi.decode(payload, (address, bool));
            automation.reactiveSetHookCaller(jobId, caller, allowed);
            return;
        }
        if (action == ACTION_SET_WORLD_VERIFIER) {
            (address newVerifier, uint256 newGroupId) = abi.decode(payload, (address, uint256));
            automation.reactiveSetWorldVerifier(jobId, newVerifier, newGroupId);
            return;
        }
        if (action == ACTION_SET_SELF_REGISTRY) {
            automation.reactiveSetSelfRegistry(jobId, abi.decode(payload, (address)));
            return;
        }
        if (action == ACTION_SET_SELF_TRUSTED_SIGNER) {
            (address signer, bool allowed) = abi.decode(payload, (address, bool));
            automation.reactiveSetSelfTrustedSigner(jobId, signer, allowed);
            return;
        }
        if (action == ACTION_PAUSE_ALL) {
            automation.reactivePauseAll(jobId, abi.decode(payload, (bool)));
            return;
        }

        revert InvalidAction(action);
    }
}
