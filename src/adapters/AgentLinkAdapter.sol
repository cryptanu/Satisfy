// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "../interfaces/ICredentialAdapter.sol";
import {ICredentialAdapterV2} from "../interfaces/ICredentialAdapterV2.sol";
import {ECDSA} from "../utils/ECDSA.sol";
import {Ownable} from "../utils/Ownable.sol";

contract AgentLinkAdapter is ICredentialAdapter, ICredentialAdapterV2, Ownable {
    using ECDSA for bytes32;

    struct AgentLinkProofV1 {
        bytes32 humanIdHash;
        uint64 issuedAt;
        uint64 validUntil;
        uint256 relayNonce;
        bytes32 sourceBridgeId;
        bytes signature;
    }

    struct AgentLinkConditionV1 {
        bool requireLinkedHuman;
        bytes32 policyContext;
        uint64 maxProofAge;
        bytes32 requiredSourceBridgeId;
    }

    bytes32 public constant PROOF_TYPEHASH = keccak256(
        "AgentLinkProofV1(address user,uint256 policyId,uint64 epoch,bytes32 bundleNullifier,bytes32 humanIdHash,uint64 issuedAt,uint64 validUntil,uint256 relayNonce,bytes32 policyContext,bytes32 sourceBridgeId)"
    );

    mapping(address => bool) public trustedSigners;

    error InvalidSigner();

    event TrustedSignerUpdated(address indexed signer, bool allowed);

    constructor(address initialOwner, address initialTrustedSigner) Ownable(initialOwner) {
        if (initialTrustedSigner != address(0)) {
            trustedSigners[initialTrustedSigner] = true;
            emit TrustedSignerUpdated(initialTrustedSigner, true);
        }
    }

    function setTrustedSigner(address signer, bool allowed) external onlyOwner {
        if (signer == address(0)) revert InvalidSigner();
        trustedSigners[signer] = allowed;
        emit TrustedSignerUpdated(signer, allowed);
    }

    function verify(address user, bytes calldata proofPayload, bytes calldata policyCondition)
        external
        view
        override
        returns (bool)
    {
        return _verify(user, proofPayload, policyCondition, bytes32(0), 0, 0, false);
    }

    function verifyWithContext(
        address user,
        bytes calldata proofPayload,
        bytes calldata policyCondition,
        bytes32 bundleNullifier,
        uint64 epoch,
        uint256 policyId
    ) external view override returns (bool) {
        return _verify(user, proofPayload, policyCondition, bundleNullifier, epoch, policyId, true);
    }

    function proofDigest(
        address user,
        uint256 policyId,
        uint64 epoch,
        bytes32 bundleNullifier,
        bytes32 humanIdHash,
        uint64 issuedAt,
        uint64 validUntil,
        uint256 relayNonce,
        bytes32 policyContext,
        bytes32 sourceBridgeId
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PROOF_TYPEHASH,
                user,
                policyId,
                epoch,
                bundleNullifier,
                humanIdHash,
                issuedAt,
                validUntil,
                relayNonce,
                policyContext,
                sourceBridgeId
            )
        ).toEthSignedMessageHash();
    }

    function _verify(
        address user,
        bytes calldata proofPayload,
        bytes calldata policyCondition,
        bytes32 bundleNullifier,
        uint64 epoch,
        uint256 policyId,
        bool withContext
    ) internal view returns (bool) {
        AgentLinkProofV1 memory proof = abi.decode(proofPayload, (AgentLinkProofV1));

        AgentLinkConditionV1 memory condition = AgentLinkConditionV1({
            requireLinkedHuman: true,
            policyContext: bytes32(0),
            maxProofAge: 0,
            requiredSourceBridgeId: bytes32(0)
        });
        if (policyCondition.length > 0) {
            condition = abi.decode(policyCondition, (AgentLinkConditionV1));
        }

        if (!condition.requireLinkedHuman) return true;
        if (!withContext) return false;

        if (proof.humanIdHash == bytes32(0)) return false;
        if (proof.validUntil <= proof.issuedAt) return false;
        if (proof.validUntil < block.timestamp) return false;
        if (proof.issuedAt > block.timestamp) return false;
        if (condition.maxProofAge != 0 && block.timestamp > uint256(proof.issuedAt) + condition.maxProofAge) return false;
        if (
            condition.requiredSourceBridgeId != bytes32(0) && proof.sourceBridgeId != condition.requiredSourceBridgeId
        ) {
            return false;
        }

        bytes32 expectedNullifier = keccak256(abi.encode(policyId, epoch, proof.humanIdHash, condition.policyContext));
        if (bundleNullifier != expectedNullifier) return false;

        bytes32 digest = proofDigest(
            user,
            policyId,
            epoch,
            bundleNullifier,
            proof.humanIdHash,
            proof.issuedAt,
            proof.validUntil,
            proof.relayNonce,
            condition.policyContext,
            proof.sourceBridgeId
        );
        address signer = digest.recover(proof.signature);
        return trustedSigners[signer];
    }
}
