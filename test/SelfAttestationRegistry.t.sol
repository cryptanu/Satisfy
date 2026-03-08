// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SelfAttestationRegistry} from "../src/SelfAttestationRegistry.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract SelfAttestationRegistryTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant SIGNER_PK = 0x1111;
    uint256 private constant OTHER_SIGNER_PK = 0x2222;

    SelfAttestationRegistry internal registry;
    address internal trustedSigner;

    function setUp() public {
        trustedSigner = vm.addr(SIGNER_PK);
        registry = new SelfAttestationRegistry(address(this), trustedSigner);
    }

    function testSubmitAndReadAttestation() public {
        SelfAttestationRegistry.AttestationPayloadV1 memory payload = _payload(
            keccak256("att-1"),
            address(0x1234),
            21,
            true,
            false,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            keccak256("ctx-1"),
            0
        );

        bytes memory signature = _signPayload(payload, SIGNER_PK);
        registry.submitAttestation(payload, signature);

        SelfAttestationRegistry.AttestationRecord memory record = registry.getAttestation(payload.attestationId);
        require(record.exists, "attestation should exist");
        require(record.subject == payload.subject, "subject mismatch");
        require(record.age == payload.age, "age mismatch");
        require(record.contributor == payload.contributor, "contributor mismatch");
        require(record.daoMember == payload.daoMember, "dao member mismatch");
        require(record.context == payload.context, "context mismatch");
        require(!record.revoked, "record should not be revoked");
        require(registry.nextNonce(trustedSigner) == 1, "nonce should increment");
    }

    function testNonceReplayRejected() public {
        SelfAttestationRegistry.AttestationPayloadV1 memory payload = _payload(
            keccak256("att-2"),
            address(0x2345),
            33,
            true,
            true,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            keccak256("ctx-2"),
            0
        );

        bytes memory sig = _signPayload(payload, SIGNER_PK);
        registry.submitAttestation(payload, sig);

        SelfAttestationRegistry.AttestationPayloadV1 memory replayPayload = _payload(
            keccak256("att-3"),
            address(0x2345),
            33,
            true,
            true,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            keccak256("ctx-2"),
            0
        );

        bytes memory replaySig = _signPayload(replayPayload, SIGNER_PK);
        (bool success,) =
            address(registry).call(abi.encodeWithSelector(registry.submitAttestation.selector, replayPayload, replaySig));
        require(!success, "replayed nonce should fail");
    }

    function testInvalidSignerRejected() public {
        SelfAttestationRegistry.AttestationPayloadV1 memory payload = _payload(
            keccak256("att-4"),
            address(0x3456),
            19,
            false,
            false,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            keccak256("ctx-3"),
            0
        );

        bytes memory sig = _signPayload(payload, OTHER_SIGNER_PK);
        (bool success,) = address(registry).call(abi.encodeWithSelector(registry.submitAttestation.selector, payload, sig));
        require(!success, "non-trusted signer should fail");
    }

    function testDomainSeparationRejectsCrossContractDigest() public {
        SelfAttestationRegistry otherRegistry = new SelfAttestationRegistry(address(this), trustedSigner);

        SelfAttestationRegistry.AttestationPayloadV1 memory payload = _payload(
            keccak256("att-5"),
            address(0x4567),
            40,
            true,
            false,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            keccak256("ctx-4"),
            0
        );

        bytes32 foreignDigest = otherRegistry.attestationDigest(payload);
        bytes memory signature = _signDigest(SIGNER_PK, foreignDigest);

        (bool success,) =
            address(registry).call(abi.encodeWithSelector(registry.submitAttestation.selector, payload, signature));
        require(!success, "signature from different registry domain should fail");
    }

    function testRevokeAttestation() public {
        SelfAttestationRegistry.AttestationPayloadV1 memory payload = _payload(
            keccak256("att-6"),
            address(0x5678),
            29,
            false,
            true,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            keccak256("ctx-5"),
            0
        );

        bytes memory signature = _signPayload(payload, SIGNER_PK);
        registry.submitAttestation(payload, signature);

        registry.revokeAttestation(payload.attestationId);
        SelfAttestationRegistry.AttestationRecord memory record = registry.getAttestation(payload.attestationId);
        require(record.revoked, "attestation should be revoked");
    }

    function _payload(
        bytes32 attestationId,
        address subject,
        uint8 age,
        bool contributor,
        bool daoMember,
        uint64 issuedAt,
        uint64 expiresAt,
        bytes32 context,
        uint256 nonce
    ) internal pure returns (SelfAttestationRegistry.AttestationPayloadV1 memory) {
        return SelfAttestationRegistry.AttestationPayloadV1({
            attestationId: attestationId,
            subject: subject,
            age: age,
            contributor: contributor,
            daoMember: daoMember,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            context: context,
            nonce: nonce
        });
    }

    function _signPayload(SelfAttestationRegistry.AttestationPayloadV1 memory payload, uint256 privateKey)
        internal
        returns (bytes memory)
    {
        bytes32 digest = registry.attestationDigest(payload);
        return _signDigest(privateKey, digest);
    }

    function _signDigest(uint256 privateKey, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
