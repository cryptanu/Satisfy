// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "../interfaces/ICredentialAdapter.sol";
import {IWorldIdVerifier} from "../interfaces/IWorldIdVerifier.sol";
import {Ownable} from "../utils/Ownable.sol";

contract WorldIdAdapter is ICredentialAdapter, Ownable {
    struct WorldIdProofV1 {
        uint256 root;
        uint256 nullifierHash;
        uint256[8] proof;
        uint64 issuedAt;
        uint64 validUntil;
        bytes32 signal;
        bytes32 externalNullifier;
    }

    struct WorldConditionV1 {
        bool requireHuman;
        bytes32 externalNullifier;
        bytes32 policyContext;
        uint64 maxProofAge;
    }

    IWorldIdVerifier public verifier;
    uint256 public groupId;

    error InvalidVerifier();

    event VerifierUpdated(address indexed previousVerifier, address indexed newVerifier, uint256 indexed newGroupId);

    constructor(address initialOwner, address initialVerifier, uint256 initialGroupId) Ownable(initialOwner) {
        if (initialVerifier == address(0)) revert InvalidVerifier();
        verifier = IWorldIdVerifier(initialVerifier);
        groupId = initialGroupId;
        emit VerifierUpdated(address(0), initialVerifier, initialGroupId);
    }

    function setVerifier(address newVerifier, uint256 newGroupId) external onlyOwner {
        if (newVerifier == address(0)) revert InvalidVerifier();
        address oldVerifier = address(verifier);
        verifier = IWorldIdVerifier(newVerifier);
        groupId = newGroupId;
        emit VerifierUpdated(oldVerifier, newVerifier, newGroupId);
    }

    function verify(address user, bytes calldata proofPayload, bytes calldata policyCondition)
        external
        view
        override
        returns (bool)
    {
        WorldIdProofV1 memory proof = abi.decode(proofPayload, (WorldIdProofV1));

        WorldConditionV1 memory condition = WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: bytes32(0),
            maxProofAge: 0
        });
        if (policyCondition.length > 0) {
            condition = abi.decode(policyCondition, (WorldConditionV1));
        }

        if (!condition.requireHuman) return true;
        if (proof.validUntil < block.timestamp) return false;
        if (proof.issuedAt > block.timestamp) return false;
        if (condition.maxProofAge != 0 && block.timestamp > uint256(proof.issuedAt) + condition.maxProofAge) {
            return false;
        }
        bytes32 expectedExternalNullifier = condition.externalNullifier;
        if (expectedExternalNullifier == bytes32(0)) {
            expectedExternalNullifier = keccak256(abi.encodePacked(block.chainid, address(this), condition.policyContext));
        }
        if (proof.externalNullifier != expectedExternalNullifier) {
            return false;
        }

        bytes32 expectedSignal =
            keccak256(abi.encodePacked(block.chainid, address(this), user, condition.policyContext, expectedExternalNullifier));
        if (proof.signal != expectedSignal) return false;

        try verifier.verifyProof(
            proof.root,
            groupId,
            uint256(proof.signal),
            proof.nullifierHash,
            uint256(proof.externalNullifier),
            proof.proof
        ) {
            return true;
        } catch {
            return false;
        }
    }
}
