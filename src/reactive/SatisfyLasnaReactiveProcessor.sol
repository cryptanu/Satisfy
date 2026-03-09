// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractReactive} from "reactive-lib/abstract-base/AbstractReactive.sol";
import {Ownable} from "../utils/Ownable.sol";

/// @notice Reactive Network (Lasna) contract that watches source-chain registry events
/// and emits callbacks to the destination-chain callback receiver.
contract SatisfyLasnaReactiveProcessor is AbstractReactive, Ownable {
    uint256 public constant TOPIC_ATTESTATION_REVOKED = uint256(keccak256("AttestationRevoked(bytes32,address)"));
    uint256 public constant TOPIC_TRUSTED_SIGNER_UPDATED = uint256(keccak256("TrustedSignerUpdated(address,bool)"));

    uint256 public immutable sourceChainId;
    address public immutable sourceRegistry;
    uint256 public immutable destinationChainId;
    address public immutable destinationCallback;
    uint64 public immutable destinationGasLimit;
    bool public immutable revocationRotateEpoch;
    bool public immutable signerDisablePause;

    event ReactiveForwarded(uint8 indexed action, bytes32 indexed jobId, uint256 indexed sourceTxHash, uint256 logIndex);

    constructor(
        address initialOwner,
        uint256 sourceChainId_,
        address sourceRegistry_,
        uint256 destinationChainId_,
        address destinationCallback_,
        uint64 destinationGasLimit_,
        bool revocationRotateEpoch_,
        bool signerDisablePause_
    ) payable Ownable(initialOwner) {
        require(sourceChainId_ != 0, "invalid source chain");
        require(sourceRegistry_ != address(0), "invalid source registry");
        require(destinationChainId_ != 0, "invalid destination chain");
        require(destinationCallback_ != address(0), "invalid callback");

        sourceChainId = sourceChainId_;
        sourceRegistry = sourceRegistry_;
        destinationChainId = destinationChainId_;
        destinationCallback = destinationCallback_;
        destinationGasLimit = destinationGasLimit_;
        revocationRotateEpoch = revocationRotateEpoch_;
        signerDisablePause = signerDisablePause_;

        // Subscriptions are configured on the Reactive Network copy (not VM copies).
        if (!vm) {
            service.subscribe(
                sourceChainId, sourceRegistry, TOPIC_ATTESTATION_REVOKED, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
            service.subscribe(
                sourceChainId,
                sourceRegistry,
                TOPIC_TRUSTED_SIGNER_UPDATED,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(LogRecord calldata log) external vmOnly {
        if (log.chain_id != sourceChainId || log._contract != sourceRegistry) return;

        if (log.topic_0 == TOPIC_ATTESTATION_REVOKED) {
            if (!revocationRotateEpoch) return;
            bytes32 jobId = _jobId("revocation", log);
            bytes memory payload = abi.encodeWithSignature("handleRevocation(address,bytes32)", address(0), jobId);
            emit Callback(destinationChainId, destinationCallback, destinationGasLimit, payload);
            emit ReactiveForwarded(0, jobId, log.tx_hash, log.log_index);
            return;
        }

        if (log.topic_0 == TOPIC_TRUSTED_SIGNER_UPDATED) {
            if (!signerDisablePause) return;
            if (_decodeBool(log.data)) return;
            bytes32 jobId = _jobId("signer-disable", log);
            bytes memory payload = abi.encodeWithSignature("handleSignerDisable(address,bytes32)", address(0), jobId);
            emit Callback(destinationChainId, destinationCallback, destinationGasLimit, payload);
            emit ReactiveForwarded(1, jobId, log.tx_hash, log.log_index);
        }
    }

    function _decodeBool(bytes calldata encodedBool) internal pure returns (bool value) {
        if (encodedBool.length < 32) return false;
        assembly {
            value := calldataload(encodedBool.offset)
        }
    }

    function _jobId(string memory label, LogRecord calldata log) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "SATISFY_LASNA_REACTIVE_V1", label, log.chain_id, log._contract, log.tx_hash, log.log_index, log.topic_1
            )
        );
    }
}
