// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyPolicyEngine} from "../src/SatisfyPolicyEngine.sol";
import {SatisfyTypes} from "../src/types/SatisfyTypes.sol";
import {MockCredentialAdapter} from "./mocks/MockCredentialAdapter.sol";
import {MockContextCredentialAdapter} from "./mocks/MockContextCredentialAdapter.sol";

contract SatisfyPolicyEngineV2Test {
    bytes32 private constant ADAPTER_WORLD = keccak256("WORLD");
    bytes32 private constant ADAPTER_SELF = keccak256("SELF");
    bytes32 private constant ADAPTER_AGENT = keccak256("AGENT_LINK");

    bytes32 private constant TAG_HUMAN = keccak256("HUMAN");
    bytes32 private constant TAG_DAO = keccak256("DAO_MEMBER");
    bytes32 private constant TAG_AGENT = keccak256("AGENT");

    address private constant USER = address(0xBEEF);

    SatisfyPolicyEngine internal engine;
    MockCredentialAdapter internal worldAdapter;
    MockCredentialAdapter internal selfAdapter;
    MockContextCredentialAdapter internal agentAdapter;

    function setUp() public {
        engine = new SatisfyPolicyEngine(address(this));
        worldAdapter = new MockCredentialAdapter();
        selfAdapter = new MockCredentialAdapter();
        agentAdapter = new MockContextCredentialAdapter();

        engine.registerAdapter(ADAPTER_WORLD, address(worldAdapter));
        engine.registerAdapter(ADAPTER_SELF, address(selfAdapter));
        engine.registerAdapter(ADAPTER_AGENT, address(agentAdapter));
    }

    function testCreatePolicyV2SupportsDnfGroups() public {
        SatisfyTypes.PredicateGroup[] memory groups = new SatisfyTypes.PredicateGroup[](2);
        groups[0].predicates = new SatisfyTypes.Predicate[](2);
        groups[0].predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_WORLD, condition: abi.encode(TAG_HUMAN)});
        groups[0].predicates[1] = SatisfyTypes.Predicate({adapterId: ADAPTER_SELF, condition: abi.encode(TAG_DAO)});

        groups[1].predicates = new SatisfyTypes.Predicate[](1);
        groups[1].predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_AGENT, condition: abi.encode(TAG_AGENT)});

        uint256 policyId = engine.createPolicyV2(groups, 0, 0, true);

        uint64 epoch = engine.currentEpoch();
        bytes32 group0Nullifier = bytes32("g0");
        SatisfyTypes.Proof[] memory group0Proofs = new SatisfyTypes.Proof[](2);
        group0Proofs[0] = SatisfyTypes.Proof({adapterId: ADAPTER_WORLD, payload: abi.encode(TAG_HUMAN, USER)});
        group0Proofs[1] = SatisfyTypes.Proof({adapterId: ADAPTER_SELF, payload: abi.encode(TAG_DAO, USER)});
        SatisfyTypes.ProofBundle memory group0Bundle =
            SatisfyTypes.ProofBundle({proofs: group0Proofs, nullifier: group0Nullifier, epoch: epoch});

        bool group0Ok = engine.satisfies(policyId, USER, group0Bundle);
        require(group0Ok, "group0 should satisfy");

        bytes32 group1Nullifier = keccak256("group1-nullifier");
        SatisfyTypes.Proof[] memory group1Proofs = new SatisfyTypes.Proof[](1);
        group1Proofs[0] = SatisfyTypes.Proof({
            adapterId: ADAPTER_AGENT,
            payload: abi.encode(TAG_AGENT, USER, group1Nullifier, epoch, policyId)
        });
        SatisfyTypes.ProofBundle memory group1Bundle =
            SatisfyTypes.ProofBundle({proofs: group1Proofs, nullifier: group1Nullifier, epoch: epoch});

        bool group1Ok = engine.satisfies(policyId, USER, group1Bundle);
        require(group1Ok, "group1 should satisfy through context-aware adapter");

        bool consumed = engine.validateAndConsume(policyId, USER, group1Bundle);
        require(consumed, "consume should pass for valid context proof");
    }

    function testCreatePolicyV2RejectsWrongContextNullifier() public {
        SatisfyTypes.PredicateGroup[] memory groups = new SatisfyTypes.PredicateGroup[](1);
        groups[0].predicates = new SatisfyTypes.Predicate[](1);
        groups[0].predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_AGENT, condition: abi.encode(TAG_AGENT)});

        uint256 policyId = engine.createPolicyV2(groups, 0, 0, true);
        uint64 epoch = engine.currentEpoch();

        bytes32 expectedNullifier = keccak256("expected");
        SatisfyTypes.Proof[] memory proofs = new SatisfyTypes.Proof[](1);
        proofs[0] = SatisfyTypes.Proof({
            adapterId: ADAPTER_AGENT,
            payload: abi.encode(TAG_AGENT, USER, expectedNullifier, epoch, policyId)
        });
        SatisfyTypes.ProofBundle memory bundle =
            SatisfyTypes.ProofBundle({proofs: proofs, nullifier: keccak256("wrong"), epoch: epoch});

        bool ok = engine.satisfies(policyId, USER, bundle);
        require(!ok, "wrong bundle nullifier should fail context adapter verification");
    }

    function testGroupGettersExposeV2Structure() public {
        SatisfyTypes.PredicateGroup[] memory groups = new SatisfyTypes.PredicateGroup[](2);
        groups[0].predicates = new SatisfyTypes.Predicate[](1);
        groups[0].predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_WORLD, condition: abi.encode(TAG_HUMAN)});
        groups[1].predicates = new SatisfyTypes.Predicate[](1);
        groups[1].predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_AGENT, condition: abi.encode(TAG_AGENT)});

        uint256 policyId = engine.createPolicyV2(groups, 0, 0, true);

        uint256 groupCount = engine.getPolicyGroupCount(policyId);
        require(groupCount == 2, "group count mismatch");

        uint256 predicateCount = engine.getPolicyGroupPredicateCount(policyId, 1);
        require(predicateCount == 1, "group predicate count mismatch");

        (bytes32 adapterId,) = engine.getPolicyGroupPredicate(policyId, 1, 0);
        require(adapterId == ADAPTER_AGENT, "group predicate adapter mismatch");
    }
}
