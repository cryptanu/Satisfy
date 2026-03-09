// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "../utils/Ownable.sol";

interface IReactiveGatewayDispatch {
    function ACTION_SET_EPOCH() external view returns (uint8);
    function ACTION_PAUSE_ALL() external view returns (uint8);
    function executeFromReactiveCallback(bytes32 jobId, uint8 action, bytes calldata payload) external;
}

interface IReactivePolicyEngineState {
    function currentEpoch() external view returns (uint64);
    function paused() external view returns (bool);
}

/// @notice Destination-chain callback receiver for Reactive Network callbacks.
/// Callback payload signatures use the first argument as `address rvmId`.
contract SatisfyReactiveCallbackReceiver is Ownable {
    address public callbackSender;
    address public reactiveOwner;

    IReactiveGatewayDispatch public immutable gateway;
    IReactivePolicyEngineState public immutable policyEngine;

    error InvalidAddress();
    error UnauthorizedCallbackSender(address sender);
    error UnauthorizedReactiveOwner(address rvmId);

    event CallbackSenderUpdated(address indexed oldSender, address indexed newSender);
    event ReactiveOwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event RevocationHandled(address indexed rvmId, bytes32 indexed jobId, uint64 nextEpoch);
    event SignerDisableHandled(address indexed rvmId, bytes32 indexed jobId);

    constructor(
        address initialOwner,
        address initialCallbackSender,
        address initialReactiveOwner,
        address gatewayAddress,
        address policyEngineAddress
    ) Ownable(initialOwner) {
        if (
            initialCallbackSender == address(0) || initialReactiveOwner == address(0) || gatewayAddress == address(0)
                || policyEngineAddress == address(0)
        ) revert InvalidAddress();

        callbackSender = initialCallbackSender;
        reactiveOwner = initialReactiveOwner;
        gateway = IReactiveGatewayDispatch(gatewayAddress);
        policyEngine = IReactivePolicyEngineState(policyEngineAddress);
    }

    modifier onlyCallbackSender() {
        if (msg.sender != callbackSender) revert UnauthorizedCallbackSender(msg.sender);
        _;
    }

    modifier onlyReactiveOwner(address rvmId) {
        if (rvmId != reactiveOwner) revert UnauthorizedReactiveOwner(rvmId);
        _;
    }

    function setCallbackSender(address newSender) external onlyOwner {
        if (newSender == address(0)) revert InvalidAddress();
        address oldSender = callbackSender;
        callbackSender = newSender;
        emit CallbackSenderUpdated(oldSender, newSender);
    }

    function setReactiveOwner(address newReactiveOwner) external onlyOwner {
        if (newReactiveOwner == address(0)) revert InvalidAddress();
        address oldOwner = reactiveOwner;
        reactiveOwner = newReactiveOwner;
        emit ReactiveOwnerUpdated(oldOwner, newReactiveOwner);
    }

    /// @notice Called by callback proxy when AttestationRevoked is observed.
    function handleRevocation(address rvmId, bytes32 jobId) external onlyCallbackSender onlyReactiveOwner(rvmId) {
        uint64 nextEpoch = policyEngine.currentEpoch() + 1;
        gateway.executeFromReactiveCallback(jobId, gateway.ACTION_SET_EPOCH(), abi.encode(nextEpoch));
        emit RevocationHandled(rvmId, jobId, nextEpoch);
    }

    /// @notice Called by callback proxy when TrustedSignerUpdated(..., false) is observed.
    function handleSignerDisable(address rvmId, bytes32 jobId) external onlyCallbackSender onlyReactiveOwner(rvmId) {
        if (!policyEngine.paused()) {
            gateway.executeFromReactiveCallback(jobId, gateway.ACTION_PAUSE_ALL(), abi.encode(true));
        }
        emit SignerDisableHandled(rvmId, jobId);
    }
}
