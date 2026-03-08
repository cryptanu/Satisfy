// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SelfAdapter} from "../src/adapters/SelfAdapter.sol";
import {SelfAttestationRegistry} from "../src/SelfAttestationRegistry.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 newTimestamp) external;
}

contract SelfAdapterTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant SIGNER_PK = 0xBEEF;

    address private constant USER = address(0x1234);

    SelfAttestationRegistry internal registry;
    SelfAdapter internal adapter;

    function setUp() public {
        registry = new SelfAttestationRegistry(address(this), vm.addr(SIGNER_PK));
        adapter = new SelfAdapter(address(this), address(registry));
    }

    function testVerifyValidAttestation() public {
        SelfAdapter.SelfConditionV1 memory condition = SelfAdapter.SelfConditionV1({
            minAge: 18,
            requireContributor: true,
            requireDaoMember: false,
            maxAttestationAge: 1 days
        });

        bytes memory proofPayload = _submit(USER, condition, 22, true, false, uint64(block.timestamp + 1 days));
        bool ok = adapter.verify(USER, proofPayload, abi.encode(condition));
        require(ok, "valid attestation should pass");
    }

    function testVerifyRejectsContextMismatch() public {
        SelfAdapter.SelfConditionV1 memory condition = SelfAdapter.SelfConditionV1({
            minAge: 18,
            requireContributor: false,
            requireDaoMember: false,
            maxAttestationAge: 0
        });

        bytes memory proofPayload = _submit(USER, condition, 30, true, false, uint64(block.timestamp + 1 days));

        SelfAdapter.SelfConditionV1 memory wrongCondition = SelfAdapter.SelfConditionV1({
            minAge: 18,
            requireContributor: true,
            requireDaoMember: false,
            maxAttestationAge: 0
        });

        bool ok = adapter.verify(USER, proofPayload, abi.encode(wrongCondition));
        require(!ok, "condition mismatch should fail context");
    }

    function testVerifyRejectsAgeAndContributorConstraint() public {
        SelfAdapter.SelfConditionV1 memory condition = SelfAdapter.SelfConditionV1({
            minAge: 21,
            requireContributor: true,
            requireDaoMember: false,
            maxAttestationAge: 0
        });

        bytes memory proofPayload = _submit(USER, condition, 19, false, false, uint64(block.timestamp + 1 days));
        bool ok = adapter.verify(USER, proofPayload, abi.encode(condition));
        require(!ok, "claims that do not satisfy condition should fail");
    }

    function testVerifyRejectsExpiredOrOldAttestation() public {
        vm.warp(10 days);
        SelfAdapter.SelfConditionV1 memory condition = SelfAdapter.SelfConditionV1({
            minAge: 18,
            requireContributor: false,
            requireDaoMember: false,
            maxAttestationAge: 1 hours
        });

        bytes memory conditionBytes = abi.encode(condition);
        bytes32 context = keccak256(abi.encodePacked(block.chainid, address(adapter), USER, conditionBytes));
        bytes32 attestationId = keccak256("self-old");

        SelfAttestationRegistry.AttestationPayloadV1 memory payload = SelfAttestationRegistry.AttestationPayloadV1({
            attestationId: attestationId,
            subject: USER,
            age: 22,
            contributor: false,
            daoMember: false,
            issuedAt: uint64(1 days),
            expiresAt: uint64(2 days),
            context: context,
            nonce: registry.nextNonce(vm.addr(SIGNER_PK))
        });

        registry.submitAttestation(payload, _sign(payload));
        bytes memory proofPayload =
            abi.encode(SelfAdapter.SelfAttestationProofV1({attestationId: attestationId, context: context}));

        bool ok = adapter.verify(USER, proofPayload, conditionBytes);
        require(!ok, "expired and stale attestation should fail");
    }

    function testVerifyRejectsRevokedAttestation() public {
        SelfAdapter.SelfConditionV1 memory condition = SelfAdapter.SelfConditionV1({
            minAge: 18,
            requireContributor: false,
            requireDaoMember: false,
            maxAttestationAge: 0
        });

        bytes memory conditionBytes = abi.encode(condition);
        bytes32 context = keccak256(abi.encodePacked(block.chainid, address(adapter), USER, conditionBytes));
        bytes32 attestationId = keccak256("self-revoked");

        SelfAttestationRegistry.AttestationPayloadV1 memory payload = SelfAttestationRegistry.AttestationPayloadV1({
            attestationId: attestationId,
            subject: USER,
            age: 22,
            contributor: false,
            daoMember: false,
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + 1 days),
            context: context,
            nonce: registry.nextNonce(vm.addr(SIGNER_PK))
        });

        registry.submitAttestation(payload, _sign(payload));
        registry.revokeAttestation(attestationId);

        bytes memory proofPayload =
            abi.encode(SelfAdapter.SelfAttestationProofV1({attestationId: attestationId, context: context}));

        bool ok = adapter.verify(USER, proofPayload, conditionBytes);
        require(!ok, "revoked attestation should fail");
    }

    function testMalformedPayloadReverts() public {
        SelfAdapter.SelfConditionV1 memory condition = SelfAdapter.SelfConditionV1({
            minAge: 18,
            requireContributor: false,
            requireDaoMember: false,
            maxAttestationAge: 0
        });

        (bool success,) = address(adapter).call(
            abi.encodeWithSelector(adapter.verify.selector, USER, hex"1234", abi.encode(condition))
        );
        require(!success, "malformed payload should revert decode");
    }

    function _submit(
        address subject,
        SelfAdapter.SelfConditionV1 memory condition,
        uint8 age,
        bool contributor,
        bool daoMember,
        uint64 expiresAt
    ) internal returns (bytes memory) {
        bytes memory conditionBytes = abi.encode(condition);
        bytes32 context = keccak256(abi.encodePacked(block.chainid, address(adapter), subject, conditionBytes));
        bytes32 attestationId =
            keccak256(abi.encodePacked("self", subject, age, contributor, daoMember, expiresAt, context));

        SelfAttestationRegistry.AttestationPayloadV1 memory payload = SelfAttestationRegistry.AttestationPayloadV1({
            attestationId: attestationId,
            subject: subject,
            age: age,
            contributor: contributor,
            daoMember: daoMember,
            issuedAt: uint64(block.timestamp),
            expiresAt: expiresAt,
            context: context,
            nonce: registry.nextNonce(vm.addr(SIGNER_PK))
        });

        registry.submitAttestation(payload, _sign(payload));
        return abi.encode(SelfAdapter.SelfAttestationProofV1({attestationId: attestationId, context: context}));
    }

    function _sign(SelfAttestationRegistry.AttestationPayloadV1 memory payload) internal returns (bytes memory) {
        bytes32 digest = registry.attestationDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        return abi.encodePacked(r, s, v);
    }
}
