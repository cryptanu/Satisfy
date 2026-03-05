// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyHook} from "../src/SatisfyHook.sol";
import {SatisfyPolicyEngine} from "../src/SatisfyPolicyEngine.sol";
import {SatisfyTypes} from "../src/types/SatisfyTypes.sol";
import {ECDSA} from "../src/utils/ECDSA.sol";
import {SelfAdapter} from "../src/adapters/SelfAdapter.sol";
import {WorldIdAdapter} from "../src/adapters/WorldIdAdapter.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 newTimestamp) external;
}

contract SatisfyE2ETest {
    using ECDSA for bytes32;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant WORLD_ADAPTER_ID = keccak256("WORLD_ID");
    bytes32 private constant SELF_ADAPTER_ID = keccak256("SELF");
    bytes32 private constant POOL_ID = keccak256("HUMAN_DAO_POOL");

    uint256 private constant WORLD_ISSUER_PK = 0xA11CE;
    uint256 private constant SELF_ISSUER_PK = 0xB0B;

    address private constant USER = address(0x1234);

    SatisfyPolicyEngine internal engine;
    SatisfyHook internal hook;
    WorldIdAdapter internal worldAdapter;
    SelfAdapter internal selfAdapter;

    uint256 internal policyId;

    function setUp() public {
        address worldIssuer = vm.addr(WORLD_ISSUER_PK);
        address selfIssuer = vm.addr(SELF_ISSUER_PK);

        engine = new SatisfyPolicyEngine(address(this));
        worldAdapter = new WorldIdAdapter(address(this), worldIssuer);
        selfAdapter = new SelfAdapter(address(this), selfIssuer);
        hook = new SatisfyHook(address(this), address(engine), address(this));

        engine.registerAdapter(WORLD_ADAPTER_ID, address(worldAdapter));
        engine.registerAdapter(SELF_ADAPTER_ID, address(selfAdapter));
        engine.setAuthorizedConsumer(address(hook), true);

        SatisfyTypes.Predicate[] memory predicates = new SatisfyTypes.Predicate[](2);
        predicates[0] = SatisfyTypes.Predicate({adapterId: WORLD_ADAPTER_ID, condition: abi.encode(true)});
        predicates[1] = SatisfyTypes.Predicate({
            adapterId: SELF_ADAPTER_ID,
            condition: abi.encode(
                SelfAdapter.SelfCondition({minAge: 18, requireContributor: true, requireDaoMember: false})
            )
        });

        policyId = engine.createPolicy(SatisfyTypes.LogicOp.AND, predicates, 0, 0, true);
        hook.setPoolPolicy(POOL_ID, policyId);
    }

    function testEndToEndHappyPathReplayAndEpochRotation() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);

        bytes memory worldProof = _worldProofPayload(USER, true, expiresAt);
        bytes memory selfProof = _selfProofPayload(USER, 25, true, false, expiresAt);

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
        uint64 expiresAt = uint64(block.timestamp + 1 days);

        bytes memory worldProof = _worldProofPayload(USER, true, expiresAt);
        bytes memory underageSelfProof = _selfProofPayload(USER, 16, true, false, expiresAt);

        SatisfyTypes.ProofBundle memory underageBundle =
            _bundle(worldProof, underageSelfProof, keccak256("underage-nullifier"), engine.currentEpoch());

        bool underageAllowed = engine.satisfies(policyId, USER, underageBundle);
        require(!underageAllowed, "underage proof should fail policy");

        (bool underageSwap,) =
            address(hook).call(abi.encodeWithSelector(hook.beforeSwap.selector, POOL_ID, USER, underageBundle));
        require(!underageSwap, "hook should reject underage proof");

        bytes memory validSelfProof = _selfProofPayload(USER, 21, true, false, expiresAt);
        SatisfyTypes.ProofBundle memory expiringBundle =
            _bundle(worldProof, validSelfProof, keccak256("expiring-nullifier"), engine.currentEpoch());

        vm.warp(block.timestamp + 2 days);

        bool expiredAllowed = engine.satisfies(policyId, USER, expiringBundle);
        require(!expiredAllowed, "expired credentials should fail policy");
    }

    function _worldProofPayload(address user, bool human, uint64 expiresAt) internal returns (bytes memory) {
        bytes32 digest =
            keccak256(abi.encodePacked("SATISFY_WORLD_ID_V1", user, human, expiresAt)).toEthSignedMessageHash();
        bytes memory signature = _signDigest(WORLD_ISSUER_PK, digest);
        return abi.encode(WorldIdAdapter.WorldProof({human: human, expiresAt: expiresAt, signature: signature}));
    }

    function _selfProofPayload(address user, uint8 age, bool contributor, bool daoMember, uint64 expiresAt)
        internal
        returns (bytes memory)
    {
        bytes32 digest = keccak256(abi.encodePacked("SATISFY_SELF_V1", user, age, contributor, daoMember, expiresAt))
            .toEthSignedMessageHash();

        bytes memory signature = _signDigest(SELF_ISSUER_PK, digest);

        return abi.encode(
            SelfAdapter.SelfProof({
                age: age, contributor: contributor, daoMember: daoMember, expiresAt: expiresAt, signature: signature
            })
        );
    }

    function _signDigest(uint256 privateKey, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
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
