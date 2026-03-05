// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyPolicyEngine} from "../src/SatisfyPolicyEngine.sol";
import {SatisfyTypes} from "../src/types/SatisfyTypes.sol";
import {ExternalCaller} from "./mocks/ExternalCaller.sol";
import {MockCredentialAdapter} from "./mocks/MockCredentialAdapter.sol";

contract SatisfyPolicyEngineTest {
    bytes32 private constant ADAPTER_WORLD = keccak256("WORLD");
    bytes32 private constant ADAPTER_SELF = keccak256("SELF");

    bytes32 private constant TAG_HUMAN = keccak256("HUMAN");
    bytes32 private constant TAG_DAO = keccak256("DAO_MEMBER");

    address private constant USER = address(0xBEEF);

    SatisfyPolicyEngine internal engine;
    MockCredentialAdapter internal worldAdapter;
    MockCredentialAdapter internal selfAdapter;
    ExternalCaller internal outsider;

    function setUp() public {
        engine = new SatisfyPolicyEngine(address(this));
        worldAdapter = new MockCredentialAdapter();
        selfAdapter = new MockCredentialAdapter();
        outsider = new ExternalCaller();

        engine.registerAdapter(ADAPTER_WORLD, address(worldAdapter));
        engine.registerAdapter(ADAPTER_SELF, address(selfAdapter));
    }

    function testAndPolicySatisfiesWithValidProofs() public {
        uint256 policyId = _createAndPolicy();
        SatisfyTypes.ProofBundle memory bundle =
            _bundleTwoProofs(TAG_HUMAN, TAG_DAO, bytes32("n1"), engine.currentEpoch());

        bool ok = engine.satisfies(policyId, USER, bundle);
        require(ok, "expected AND policy to satisfy");
    }

    function testAndPolicyFailsWithMissingProof() public {
        uint256 policyId = _createAndPolicy();
        SatisfyTypes.ProofBundle memory bundle =
            _bundleSingleProof(ADAPTER_WORLD, TAG_HUMAN, bytes32("n2"), engine.currentEpoch());

        bool ok = engine.satisfies(policyId, USER, bundle);
        require(!ok, "expected AND policy to fail");
    }

    function testOrPolicySatisfiesWhenAnyProofMatches() public {
        uint256 policyId = _createOrPolicy();
        SatisfyTypes.ProofBundle memory bundle =
            _bundleSingleProof(ADAPTER_SELF, TAG_DAO, bytes32("n3"), engine.currentEpoch());

        bool ok = engine.satisfies(policyId, USER, bundle);
        require(ok, "expected OR policy to satisfy");
    }

    function testPolicyWindowBlocksBeforeStart() public {
        SatisfyTypes.Predicate[] memory predicates = new SatisfyTypes.Predicate[](1);
        predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_WORLD, condition: abi.encode(TAG_HUMAN)});

        uint64 start = uint64(block.timestamp + 120);
        uint256 policyId = engine.createPolicy(SatisfyTypes.LogicOp.AND, predicates, start, 0, true);
        SatisfyTypes.ProofBundle memory bundle =
            _bundleSingleProof(ADAPTER_WORLD, TAG_HUMAN, bytes32("n4"), engine.currentEpoch());

        bool ok = engine.satisfies(policyId, USER, bundle);
        require(!ok, "expected policy window to block");
    }

    function testValidateAndConsumeRejectsReplay() public {
        uint256 policyId = _createAndPolicy();
        SatisfyTypes.ProofBundle memory bundle =
            _bundleTwoProofs(TAG_HUMAN, TAG_DAO, bytes32("n5"), engine.currentEpoch());

        bool first = engine.validateAndConsume(policyId, USER, bundle);
        require(first, "first validation should pass");

        (bool second,) =
            address(engine).call(abi.encodeWithSelector(engine.validateAndConsume.selector, policyId, USER, bundle));
        require(!second, "second validation should fail (replay)");
    }

    function testOnlyAuthorizedConsumerCanConsume() public {
        uint256 policyId = _createAndPolicy();
        SatisfyTypes.ProofBundle memory bundle =
            _bundleTwoProofs(TAG_HUMAN, TAG_DAO, bytes32("n6"), engine.currentEpoch());

        bool outsiderAttempt = outsider.callValidateAndConsume(engine, policyId, USER, bundle);
        require(!outsiderAttempt, "unauthorized consumer should fail");

        engine.setAuthorizedConsumer(address(outsider), true);
        bool authorizedAttempt = outsider.callValidateAndConsume(engine, policyId, USER, bundle);
        require(authorizedAttempt, "authorized consumer should pass");
    }

    function testEpochMismatchFailsViewAndConsume() public {
        uint256 policyId = _createAndPolicy();
        SatisfyTypes.ProofBundle memory bundle =
            _bundleTwoProofs(TAG_HUMAN, TAG_DAO, bytes32("n7"), engine.currentEpoch() + 1);

        bool viewResult = engine.satisfies(policyId, USER, bundle);
        require(!viewResult, "epoch mismatch should fail view");

        (bool consumeResult,) =
            address(engine).call(abi.encodeWithSelector(engine.validateAndConsume.selector, policyId, USER, bundle));
        require(!consumeResult, "epoch mismatch should fail consume");
    }

    function testSetEpochRequiresOwner() public {
        bool outsiderUpdate = outsider.callSetEpoch(engine, 2);
        require(!outsiderUpdate, "only owner can update epoch");

        engine.setEpoch(2);
        require(engine.currentEpoch() == 2, "epoch should update");
    }

    function _createAndPolicy() internal returns (uint256 policyId) {
        SatisfyTypes.Predicate[] memory predicates = new SatisfyTypes.Predicate[](2);
        predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_WORLD, condition: abi.encode(TAG_HUMAN)});
        predicates[1] = SatisfyTypes.Predicate({adapterId: ADAPTER_SELF, condition: abi.encode(TAG_DAO)});

        policyId = engine.createPolicy(SatisfyTypes.LogicOp.AND, predicates, 0, 0, true);
    }

    function _createOrPolicy() internal returns (uint256 policyId) {
        SatisfyTypes.Predicate[] memory predicates = new SatisfyTypes.Predicate[](2);
        predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_WORLD, condition: abi.encode(TAG_HUMAN)});
        predicates[1] = SatisfyTypes.Predicate({adapterId: ADAPTER_SELF, condition: abi.encode(TAG_DAO)});

        policyId = engine.createPolicy(SatisfyTypes.LogicOp.OR, predicates, 0, 0, true);
    }

    function _bundleTwoProofs(bytes32 worldTag, bytes32 selfTag, bytes32 nullifier, uint64 epoch)
        internal
        pure
        returns (SatisfyTypes.ProofBundle memory)
    {
        SatisfyTypes.Proof[] memory proofs = new SatisfyTypes.Proof[](2);
        proofs[0] = SatisfyTypes.Proof({adapterId: ADAPTER_WORLD, payload: abi.encode(worldTag, USER)});
        proofs[1] = SatisfyTypes.Proof({adapterId: ADAPTER_SELF, payload: abi.encode(selfTag, USER)});

        return SatisfyTypes.ProofBundle({proofs: proofs, nullifier: nullifier, epoch: epoch});
    }

    function _bundleSingleProof(bytes32 adapterId, bytes32 tag, bytes32 nullifier, uint64 epoch)
        internal
        pure
        returns (SatisfyTypes.ProofBundle memory)
    {
        SatisfyTypes.Proof[] memory proofs = new SatisfyTypes.Proof[](1);
        proofs[0] = SatisfyTypes.Proof({adapterId: adapterId, payload: abi.encode(tag, USER)});

        return SatisfyTypes.ProofBundle({proofs: proofs, nullifier: nullifier, epoch: epoch});
    }
}
