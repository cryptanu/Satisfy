// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {WorldIdAdapter} from "../src/adapters/WorldIdAdapter.sol";
import {MockWorldIdVerifier} from "../src/mocks/MockWorldIdVerifier.sol";

interface Vm {
    function warp(uint256 newTimestamp) external;
}

contract WorldIdAdapterTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address private constant USER = address(0x1234);

    MockWorldIdVerifier internal verifier;
    WorldIdAdapter internal adapter;

    function setUp() public {
        verifier = new MockWorldIdVerifier();
        adapter = new WorldIdAdapter(address(this), address(verifier), 1);
    }

    function testVerifyValidWorldProof() public {
        WorldIdAdapter.WorldConditionV1 memory condition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: keccak256("world-policy"),
            maxProofAge: 1 days
        });

        bytes memory payload = _worldProofPayload(USER, condition, uint64(block.timestamp), uint64(block.timestamp + 1 days), 1, true);
        bool ok = adapter.verify(USER, payload, abi.encode(condition));
        require(ok, "world proof should verify");
    }

    function testVerifyRejectsWrongUserBinding() public {
        WorldIdAdapter.WorldConditionV1 memory condition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: keccak256("world-policy"),
            maxProofAge: 1 days
        });

        bytes memory payload = _worldProofPayload(USER, condition, uint64(block.timestamp), uint64(block.timestamp + 1 days), 2, true);
        bool ok = adapter.verify(address(0x9999), payload, abi.encode(condition));
        require(!ok, "proof should be bound to specific user");
    }

    function testVerifyRejectsExpiredProof() public {
        vm.warp(10 days);
        WorldIdAdapter.WorldConditionV1 memory condition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: keccak256("world-policy"),
            maxProofAge: 1 days
        });

        bytes memory payload = _worldProofPayload(USER, condition, uint64(1 days), uint64(2 days), 3, true);
        bool ok = adapter.verify(USER, payload, abi.encode(condition));
        require(!ok, "expired proof must fail");
    }

    function testVerifyRejectsOverAgeProof() public {
        vm.warp(10 days);
        WorldIdAdapter.WorldConditionV1 memory condition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: keccak256("world-policy"),
            maxProofAge: 1 hours
        });

        bytes memory payload = _worldProofPayload(USER, condition, uint64(1 days), uint64(30 days), 4, true);
        bool ok = adapter.verify(USER, payload, abi.encode(condition));
        require(!ok, "proof older than max age must fail");
    }

    function testVerifyRejectsWrongPolicyContext() public {
        WorldIdAdapter.WorldConditionV1 memory condition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: keccak256("world-policy"),
            maxProofAge: 1 days
        });

        bytes memory payload = _worldProofPayload(USER, condition, uint64(block.timestamp), uint64(block.timestamp + 1 days), 5, true);

        WorldIdAdapter.WorldConditionV1 memory wrongCondition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: keccak256("different-policy"),
            maxProofAge: 1 days
        });

        bool ok = adapter.verify(USER, payload, abi.encode(wrongCondition));
        require(!ok, "policy-context mismatch must fail");
    }

    function testVerifyRejectsVerifierFailure() public {
        WorldIdAdapter.WorldConditionV1 memory condition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: keccak256("world-policy"),
            maxProofAge: 1 days
        });

        bytes memory payload = _worldProofPayload(USER, condition, uint64(block.timestamp), uint64(block.timestamp + 1 days), 6, false);
        bool ok = adapter.verify(USER, payload, abi.encode(condition));
        require(!ok, "verifier rejection must fail");
    }

    function testMalformedPayloadReverts() public {
        WorldIdAdapter.WorldConditionV1 memory condition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: keccak256("world-policy"),
            maxProofAge: 1 days
        });

        (bool success,) = address(adapter).call(
            abi.encodeWithSelector(adapter.verify.selector, USER, hex"1234", abi.encode(condition))
        );
        require(!success, "malformed payload should revert decode");
    }

    function _worldProofPayload(
        address user,
        WorldIdAdapter.WorldConditionV1 memory condition,
        uint64 issuedAt,
        uint64 validUntil,
        uint256 seed,
        bool markValid
    ) internal returns (bytes memory) {
        bytes32 externalNullifier =
            keccak256(abi.encodePacked(block.chainid, address(adapter), condition.policyContext));
        bytes32 signal =
            keccak256(abi.encodePacked(block.chainid, address(adapter), user, condition.policyContext, externalNullifier));

        uint256[8] memory proof = _proof(seed);
        uint256 root = uint256(keccak256(abi.encodePacked("root", seed)));
        uint256 nullifierHash = uint256(keccak256(abi.encodePacked("nullifier", seed)));

        verifier.setValidProof(root, adapter.groupId(), uint256(signal), nullifierHash, uint256(externalNullifier), proof, markValid);

        return abi.encode(
            WorldIdAdapter.WorldIdProofV1({
                root: root,
                nullifierHash: nullifierHash,
                proof: proof,
                issuedAt: issuedAt,
                validUntil: validUntil,
                signal: signal,
                externalNullifier: externalNullifier
            })
        );
    }

    function _proof(uint256 seed) internal pure returns (uint256[8] memory arr) {
        for (uint256 i = 0; i < 8; ++i) {
            arr[i] = uint256(keccak256(abi.encodePacked(seed, i)));
        }
    }
}
