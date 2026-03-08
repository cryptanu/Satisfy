// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyHook} from "../src/SatisfyHook.sol";
import {SatisfyPolicyEngine} from "../src/SatisfyPolicyEngine.sol";
import {SatisfyTypes} from "../src/types/SatisfyTypes.sol";
import {ExternalCaller} from "./mocks/ExternalCaller.sol";
import {MockCredentialAdapter} from "./mocks/MockCredentialAdapter.sol";

contract SatisfyHookTest {
    bytes32 private constant ADAPTER_WORLD = keccak256("WORLD");
    bytes32 private constant TAG_HUMAN = keccak256("HUMAN");
    bytes32 private constant POOL_ID = keccak256("SATISFY_POOL");

    address private constant USER = address(0xFEE1);

    SatisfyPolicyEngine internal engine;
    SatisfyHook internal hook;
    MockCredentialAdapter internal worldAdapter;
    ExternalCaller internal outsider;

    uint256 internal policyId;

    function setUp() public {
        engine = new SatisfyPolicyEngine(address(this));
        hook = new SatisfyHook(address(this), address(engine), address(this));
        worldAdapter = new MockCredentialAdapter();
        outsider = new ExternalCaller();

        engine.registerAdapter(ADAPTER_WORLD, address(worldAdapter));
        engine.setAuthorizedConsumer(address(hook), true);

        SatisfyTypes.Predicate[] memory predicates = new SatisfyTypes.Predicate[](1);
        predicates[0] = SatisfyTypes.Predicate({adapterId: ADAPTER_WORLD, condition: abi.encode(TAG_HUMAN)});

        policyId = engine.createPolicy(SatisfyTypes.LogicOp.AND, predicates, 0, 0, true);
        hook.setPoolPolicy(POOL_ID, policyId);
    }

    function testBeforeSwapConsumesProof() public {
        SatisfyTypes.ProofBundle memory bundle = _bundle(bytes32("hook1"), engine.currentEpoch());

        bytes4 selector = hook.beforeSwap(POOL_ID, USER, bundle);
        require(selector == hook.beforeSwap.selector, "hook should return selector");

        (bool replay,) = address(hook).call(abi.encodeWithSelector(hook.beforeSwap.selector, POOL_ID, USER, bundle));
        require(!replay, "replay call should fail");
    }

    function testBeforeSwapRejectsUnauthorizedCaller() public {
        SatisfyTypes.ProofBundle memory bundle = _bundle(bytes32("hook2"), engine.currentEpoch());

        bool outsiderCall = outsider.callBeforeSwap(hook, POOL_ID, USER, bundle);
        require(!outsiderCall, "unauthorized hook caller should fail");
    }

    function testBeforeSwapRejectsMissingPoolPolicy() public {
        SatisfyTypes.ProofBundle memory bundle = _bundle(bytes32("hook3"), engine.currentEpoch());
        bytes32 unknownPool = keccak256("UNKNOWN_POOL");

        (bool success,) =
            address(hook).call(abi.encodeWithSelector(hook.beforeSwap.selector, unknownPool, USER, bundle));
        require(!success, "missing pool policy should fail");
    }

    function testSetPoolPolicyRequiresOwner() public {
        bool outsiderSet = outsider.callSetPoolPolicy(hook, POOL_ID, policyId);
        require(!outsiderSet, "only owner should set pool policy");
    }

    function testHookPauseBlocksBeforeSwap() public {
        SatisfyTypes.ProofBundle memory bundle = _bundle(bytes32("hook4"), engine.currentEpoch());

        hook.setPaused(true);
        (bool success,) = address(hook).call(abi.encodeWithSelector(hook.beforeSwap.selector, POOL_ID, USER, bundle));
        require(!success, "paused hook should reject beforeSwap");

        hook.setPaused(false);
        bytes4 selector = hook.beforeSwap(POOL_ID, USER, bundle);
        require(selector == hook.beforeSwap.selector, "unpaused hook should accept call");
    }

    function testSetPauseRequiresOwner() public {
        bool outsiderPause = outsider.callSetHookPaused(hook, true);
        require(!outsiderPause, "only owner should pause hook");
    }

    function _bundle(bytes32 nullifier, uint64 epoch) internal pure returns (SatisfyTypes.ProofBundle memory) {
        SatisfyTypes.Proof[] memory proofs = new SatisfyTypes.Proof[](1);
        proofs[0] = SatisfyTypes.Proof({adapterId: ADAPTER_WORLD, payload: abi.encode(TAG_HUMAN, USER)});

        return SatisfyTypes.ProofBundle({proofs: proofs, nullifier: nullifier, epoch: epoch});
    }
}
