// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ECDSA} from "./utils/ECDSA.sol";
import {ISelfAttestationRegistry} from "./interfaces/ISelfAttestationRegistry.sol";
import {Ownable} from "./utils/Ownable.sol";

contract SelfAttestationRegistry is ISelfAttestationRegistry, Ownable {
    using ECDSA for bytes32;

    struct AttestationPayloadV1 {
        bytes32 attestationId;
        address subject;
        uint8 age;
        bool contributor;
        bool daoMember;
        uint64 issuedAt;
        uint64 expiresAt;
        bytes32 context;
        uint64 sourceChainId;
        bytes32 sourceBridgeId;
        bytes32 sourceTxHash;
        uint32 sourceLogIndex;
        uint256 nonce;
    }

    bytes32 public constant ATTESTATION_TYPEHASH =
        keccak256(
            "SelfAttestationV1(bytes32 attestationId,address subject,uint8 age,bool contributor,bool daoMember,uint64 issuedAt,uint64 expiresAt,bytes32 context,uint64 sourceChainId,bytes32 sourceBridgeId,bytes32 sourceTxHash,uint32 sourceLogIndex,uint256 nonce)"
        );

    mapping(bytes32 => AttestationRecord) private attestationById;
    mapping(address => bool) public trustedSigners;
    mapping(address => uint256) public nextNonce;

    error AttestationAlreadyExists(bytes32 attestationId);
    error InvalidSigner();
    error InvalidSubject();
    error InvalidTimeRange();
    error InvalidBridgeReference();
    error InvalidNonce(uint256 expected, uint256 actual);

    event AttestationSubmitted(bytes32 indexed attestationId, address indexed signer, address indexed subject);
    event AttestationRevoked(bytes32 indexed attestationId, address indexed actor);
    event TrustedSignerUpdated(address indexed signer, bool allowed);

    constructor(address initialOwner, address initialTrustedSigner) Ownable(initialOwner) {
        if (initialTrustedSigner != address(0)) {
            trustedSigners[initialTrustedSigner] = true;
            emit TrustedSignerUpdated(initialTrustedSigner, true);
        }
    }

    function setTrustedSigner(address signer, bool allowed) external onlyOwner {
        trustedSigners[signer] = allowed;
        emit TrustedSignerUpdated(signer, allowed);
    }

    function submitAttestation(AttestationPayloadV1 calldata payload, bytes calldata signature) external {
        if (payload.subject == address(0)) revert InvalidSubject();
        if (payload.expiresAt <= payload.issuedAt) revert InvalidTimeRange();
        if (payload.sourceChainId == 0 || payload.sourceTxHash == bytes32(0)) revert InvalidBridgeReference();
        if (attestationById[payload.attestationId].exists) revert AttestationAlreadyExists(payload.attestationId);

        bytes32 digest = _attestationDigest(payload);
        address signer = digest.recover(signature);
        if (!trustedSigners[signer]) revert InvalidSigner();

        uint256 expectedNonce = nextNonce[signer];
        if (payload.nonce != expectedNonce) revert InvalidNonce(expectedNonce, payload.nonce);
        nextNonce[signer] = expectedNonce + 1;

        attestationById[payload.attestationId] = AttestationRecord({
            subject: payload.subject,
            age: payload.age,
            contributor: payload.contributor,
            daoMember: payload.daoMember,
            issuedAt: payload.issuedAt,
            expiresAt: payload.expiresAt,
            context: payload.context,
            sourceChainId: payload.sourceChainId,
            sourceBridgeId: payload.sourceBridgeId,
            sourceTxHash: payload.sourceTxHash,
            sourceLogIndex: payload.sourceLogIndex,
            revoked: false,
            exists: true
        });

        emit AttestationSubmitted(payload.attestationId, signer, payload.subject);
    }

    function revokeAttestation(bytes32 attestationId) external onlyOwner {
        AttestationRecord storage record = attestationById[attestationId];
        if (!record.exists) return;
        if (record.revoked) return;
        record.revoked = true;
        emit AttestationRevoked(attestationId, msg.sender);
    }

    function getAttestation(bytes32 attestationId) external view returns (AttestationRecord memory) {
        return attestationById[attestationId];
    }

    function attestationDigest(AttestationPayloadV1 calldata payload) external view returns (bytes32) {
        return _attestationDigest(payload);
    }

    function _attestationDigest(AttestationPayloadV1 calldata payload) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                ATTESTATION_TYPEHASH,
                payload.attestationId,
                payload.subject,
                payload.age,
                payload.contributor,
                payload.daoMember,
                payload.issuedAt,
                payload.expiresAt,
                payload.context,
                payload.sourceChainId,
                payload.sourceBridgeId,
                payload.sourceTxHash,
                payload.sourceLogIndex,
                payload.nonce
            )
        );

        return keccak256(abi.encodePacked("SATISFY_SELF_BRIDGE_V1", block.chainid, address(this), structHash))
            .toEthSignedMessageHash();
    }
}
