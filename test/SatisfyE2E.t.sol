// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyHook} from "../src/SatisfyHook.sol";
import {SatisfyPolicyEngine} from "../src/SatisfyPolicyEngine.sol";
import {SatisfyTypes} from "../src/types/SatisfyTypes.sol";
import {SelfAdapter} from "../src/adapters/SelfAdapter.sol";
import {WorldIdAdapter} from "../src/adapters/WorldIdAdapter.sol";
import {SelfAttestationRegistry} from "../src/SelfAttestationRegistry.sol";
import {MockWorldIdVerifier} from "../src/mocks/MockWorldIdVerifier.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 newTimestamp) external;
}

contract SatisfyE2ETest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant WORLD_ADAPTER_ID = keccak256("WORLD_ID");
    bytes32 private constant SELF_ADAPTER_ID = keccak256("SELF");
    bytes32 private constant POOL_ID = keccak256("HUMAN_DAO_POOL");
    bytes32 private constant WORLD_POLICY_CONTEXT = keccak256("WORLD_CTX_V1");

    uint256 private constant SELF_SIGNER_PK = 0xB0B;

    address private constant USER = address(0x1234);

    SatisfyPolicyEngine internal engine;
    SatisfyHook internal hook;
    WorldIdAdapter internal worldAdapter;
    SelfAdapter internal selfAdapter;
    SelfAttestationRegistry internal selfRegistry;
    MockWorldIdVerifier internal worldVerifier;

    uint256 internal policyId;
    WorldIdAdapter.WorldConditionV1 internal worldCondition;
    SelfAdapter.SelfConditionV1 internal selfCondition;

    function setUp() public {
        address selfSigner = vm.addr(SELF_SIGNER_PK);

        engine = new SatisfyPolicyEngine(address(this));
        worldVerifier = new MockWorldIdVerifier();
        selfRegistry = new SelfAttestationRegistry(address(this), selfSigner);

        worldAdapter = new WorldIdAdapter(address(this), address(worldVerifier), 1);
        selfAdapter = new SelfAdapter(address(this), address(selfRegistry));
        hook = new SatisfyHook(address(this), address(engine), address(this));

        engine.registerAdapter(WORLD_ADAPTER_ID, address(worldAdapter));
        engine.registerAdapter(SELF_ADAPTER_ID, address(selfAdapter));
        engine.setAuthorizedConsumer(address(hook), true);

        worldCondition = WorldIdAdapter.WorldConditionV1({
            requireHuman: true,
            externalNullifier: bytes32(0),
            policyContext: WORLD_POLICY_CONTEXT,
            maxProofAge: uint64(1 days)
        });

        selfCondition = SelfAdapter.SelfConditionV1({
            minAge: 18,
            requireContributor: true,
            requireDaoMember: false,
            maxAttestationAge: uint64(1 days)
        });

        SatisfyTypes.Predicate[] memory predicates = new SatisfyTypes.Predicate[](2);
        predicates[0] =
            SatisfyTypes.Predicate({adapterId: WORLD_ADAPTER_ID, condition: abi.encode(worldCondition)});
        predicates[1] = SatisfyTypes.Predicate({adapterId: SELF_ADAPTER_ID, condition: abi.encode(selfCondition)});

        policyId = engine.createPolicy(SatisfyTypes.LogicOp.AND, predicates, 0, 0, true);
        hook.setPoolPolicy(POOL_ID, policyId);
    }

    function testEndToEndHappyPathReplayAndEpochRotation() public {
        bytes memory worldProof = _worldProofPayload(USER, worldCondition, uint64(block.timestamp + 1 days), 77);
        bytes memory selfProof = _selfProofPayload(USER, selfCondition, 25, true, false, uint64(block.timestamp + 1 days));

        SatisfyTypes.ProofBundle memory bundle =
            _bundle(worldProof, selfProof, keccak256("nullifier-1"), engine.currentEpoch());

        bool canParticipate = engine.satisfies(policyId, USER, bundle);
        require(canParticipate, "policy should be satisfied");

        bytes4 selector = hook.beforeSwap(POOL_ID, USER, bundle);
        require(selector == hook.beforeSwap.selector, "hook should accept proof bundle");

        (bool replay,) = address(hook).call(abi.encodeWithSelector(hook.beforeSwap.selector, POOL_ID, USER, bundle));
        require(!replay, "replay should fail");

        engine.setEpoch(2);

        bool oldEpochAccepted = engine.satisfies(policyId, USER, bundle);
        require(!oldEpochAccepted, "old epoch should be rejected");

        SatisfyTypes.ProofBundle memory epochTwoBundle =
            _bundle(worldProof, selfProof, keccak256("nullifier-2"), engine.currentEpoch());

        bytes4 epochTwoSelector = hook.beforeSwap(POOL_ID, USER, epochTwoBundle);
        require(epochTwoSelector == hook.beforeSwap.selector, "new epoch bundle should pass");
    }

    function testEndToEndRejectsPolicyMismatchAndExpiredCredentials() public {
        bytes memory worldProof = _worldProofPayload(USER, worldCondition, uint64(block.timestamp + 1 days), 88);
        bytes memory underageSelfProof =
            _selfProofPayload(USER, selfCondition, 16, true, false, uint64(block.timestamp + 1 days));

        SatisfyTypes.ProofBundle memory underageBundle =
            _bundle(worldProof, underageSelfProof, keccak256("underage-nullifier"), engine.currentEpoch());

        bool underageAllowed = engine.satisfies(policyId, USER, underageBundle);
        require(!underageAllowed, "underage proof should fail policy");

        (bool underageSwap,) =
            address(hook).call(abi.encodeWithSelector(hook.beforeSwap.selector, POOL_ID, USER, underageBundle));
        require(!underageSwap, "hook should reject underage proof");

        bytes memory validSelfProof =
            _selfProofPayload(USER, selfCondition, 21, true, false, uint64(block.timestamp + 1 days));
        SatisfyTypes.ProofBundle memory expiringBundle =
            _bundle(worldProof, validSelfProof, keccak256("expiring-nullifier"), engine.currentEpoch());

        vm.warp(block.timestamp + 2 days);

        bool expiredAllowed = engine.satisfies(policyId, USER, expiringBundle);
        require(!expiredAllowed, "expired credentials should fail policy");
    }

    function _worldProofPayload(address user, WorldIdAdapter.WorldConditionV1 memory condition, uint64 validUntil, uint256 seed)
        internal
        returns (bytes memory)
    {
        bytes32 externalNullifier =
            keccak256(abi.encodePacked(block.chainid, address(worldAdapter), condition.policyContext));
        bytes32 signal =
            keccak256(abi.encodePacked(block.chainid, address(worldAdapter), user, condition.policyContext, externalNullifier));

        uint256[8] memory proof = _proofArray(seed);
        uint256 root = uint256(keccak256(abi.encodePacked("root", seed)));
        uint256 nullifierHash = uint256(keccak256(abi.encodePacked("nullifier", seed)));

        worldVerifier.setValidProof(root, worldAdapter.groupId(), uint256(signal), nullifierHash, uint256(externalNullifier), proof, true);

        WorldIdAdapter.WorldIdProofV1 memory worldProof = WorldIdAdapter.WorldIdProofV1({
            root: root,
            nullifierHash: nullifierHash,
            proof: proof,
            issuedAt: uint64(block.timestamp),
            validUntil: validUntil,
            signal: signal,
            externalNullifier: externalNullifier
        });

        return abi.encode(worldProof);
    }

    function _selfProofPayload(
        address user,
        SelfAdapter.SelfConditionV1 memory condition,
        uint8 age,
        bool contributor,
        bool daoMember,
        uint64 expiresAt
    ) internal returns (bytes memory) {
        bytes memory conditionBytes = abi.encode(condition);
        bytes32 context = keccak256(abi.encodePacked(block.chainid, address(selfAdapter), user, conditionBytes));
        bytes32 attestationId =
            keccak256(abi.encodePacked("self-attestation", user, age, contributor, daoMember, expiresAt, context));

        SelfAttestationRegistry.AttestationPayloadV1 memory payload = SelfAttestationRegistry.AttestationPayloadV1({
            attestationId: attestationId,
            subject: user,
            age: age,
            contributor: contributor,
            daoMember: daoMember,
            issuedAt: uint64(block.timestamp),
            expiresAt: expiresAt,
            context: context,
            nonce: selfRegistry.nextNonce(vm.addr(SELF_SIGNER_PK))
        });

        bytes32 digest = selfRegistry.attestationDigest(payload);
        bytes memory signature = _signDigest(SELF_SIGNER_PK, digest);
        selfRegistry.submitAttestation(payload, signature);

        return abi.encode(SelfAdapter.SelfAttestationProofV1({attestationId: attestationId, context: context}));
    }

    function _signDigest(uint256 privateKey, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _proofArray(uint256 seed) internal pure returns (uint256[8] memory proof) {
        for (uint256 i = 0; i < 8; ++i) {
            proof[i] = uint256(keccak256(abi.encodePacked(seed, i)));
        }
    }

    function _bundle(bytes memory worldProof, bytes memory selfProof, bytes32 nullifier, uint64 epoch)
        internal
        pure
        returns (SatisfyTypes.ProofBundle memory)
    {
        SatisfyTypes.Proof[] memory proofs = new SatisfyTypes.Proof[](2);
        proofs[0] = SatisfyTypes.Proof({adapterId: WORLD_ADAPTER_ID, payload: worldProof});
        proofs[1] = SatisfyTypes.Proof({adapterId: SELF_ADAPTER_ID, payload: selfProof});

        return SatisfyTypes.ProofBundle({proofs: proofs, nullifier: nullifier, epoch: epoch});
    }
}
