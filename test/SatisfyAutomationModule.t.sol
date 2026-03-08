// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyAutomationModule} from "../src/SatisfyAutomationModule.sol";
import {SatisfyHook} from "../src/SatisfyHook.sol";
import {SatisfyPolicyEngine} from "../src/SatisfyPolicyEngine.sol";
import {SatisfyTimelock} from "../src/SatisfyTimelock.sol";
import {SatisfyTypes} from "../src/types/SatisfyTypes.sol";
import {SelfAdapter} from "../src/adapters/SelfAdapter.sol";
import {WorldIdAdapter} from "../src/adapters/WorldIdAdapter.sol";
import {SelfAttestationRegistry} from "../src/SelfAttestationRegistry.sol";
import {MockWorldIdVerifier} from "../src/mocks/MockWorldIdVerifier.sol";
import {AutomationCaller} from "./mocks/AutomationCaller.sol";

interface Vm {
    function warp(uint256 newTimestamp) external;
}

contract SatisfyAutomationModuleTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant WORLD_ADAPTER_ID = keccak256("WORLD_ID");
    bytes32 private constant POOL_ID = keccak256("HUMAN_POOL");

    SatisfyPolicyEngine internal engine;
    SatisfyHook internal hook;
    WorldIdAdapter internal worldAdapter;
    SelfAdapter internal selfAdapter;
    SelfAttestationRegistry internal selfRegistry;
    MockWorldIdVerifier internal worldVerifier;
    SatisfyAutomationModule internal automation;

    AutomationCaller internal policyManager;
    AutomationCaller internal adapterManager;
    AutomationCaller internal hookManager;
    AutomationCaller internal reactiveExecutor;
    AutomationCaller internal emergencyActor;
    AutomationCaller internal outsider;

    uint256 internal policyId;

    function setUp() public {
        engine = new SatisfyPolicyEngine(address(this));
        worldVerifier = new MockWorldIdVerifier();
        selfRegistry = new SelfAttestationRegistry(address(this), address(0x1111));

        worldAdapter = new WorldIdAdapter(address(this), address(worldVerifier), 1);
        selfAdapter = new SelfAdapter(address(this), address(selfRegistry));
        hook = new SatisfyHook(address(this), address(engine), address(this));

        policyManager = new AutomationCaller();
        adapterManager = new AutomationCaller();
        hookManager = new AutomationCaller();
        reactiveExecutor = new AutomationCaller();
        emergencyActor = new AutomationCaller();
        outsider = new AutomationCaller();

        automation = new SatisfyAutomationModule(
            address(this),
            address(this),
            address(policyManager),
            address(adapterManager),
            address(hookManager),
            address(reactiveExecutor),
            address(emergencyActor),
            address(engine),
            address(hook),
            address(worldAdapter),
            address(selfAdapter),
            address(selfRegistry)
        );

        engine.transferOwnership(address(automation));
        hook.transferOwnership(address(automation));
        worldAdapter.transferOwnership(address(automation));
        selfAdapter.transferOwnership(address(automation));
        selfRegistry.transferOwnership(address(automation));

        _as(address(adapterManager), abi.encodeWithSelector(automation.registerAdapter.selector, WORLD_ADAPTER_ID, address(worldAdapter)));
        _as(address(hookManager), abi.encodeWithSelector(automation.setAuthorizedConsumer.selector, address(hook), true));

        SatisfyTypes.Predicate[] memory predicates = new SatisfyTypes.Predicate[](1);
        predicates[0] = SatisfyTypes.Predicate({
            adapterId: WORLD_ADAPTER_ID,
            condition: abi.encode(
                WorldIdAdapter.WorldConditionV1({
                    requireHuman: false,
                    externalNullifier: bytes32(0),
                    policyContext: keccak256("automation-test"),
                    maxProofAge: 0
                })
            )
        });

        bytes memory createPolicyCall = abi.encodeWithSelector(
            automation.createPolicy.selector,
            SatisfyTypes.LogicOp.AND,
            predicates,
            uint64(0),
            uint64(0),
            true
        );
        _as(address(policyManager), createPolicyCall);
        policyId = engine.policyCount();

        _as(address(hookManager), abi.encodeWithSelector(automation.setPoolPolicy.selector, POOL_ID, policyId));
    }

    function testRolePermissionsAndReactiveJobReplayProtection() public {
        bool outsiderSetEpoch = outsider.callTarget(
            address(automation), abi.encodeWithSelector(automation.setEpoch.selector, uint64(2))
        );
        require(!outsiderSetEpoch, "outsider should not set epoch");

        bool managerSetEpoch = policyManager.callTarget(
            address(automation), abi.encodeWithSelector(automation.setEpoch.selector, uint64(2))
        );
        require(managerSetEpoch, "policy manager should set epoch");
        require(engine.currentEpoch() == 2, "epoch should update");

        bytes32 replayJob = keccak256("reactive-job-replay");

        bool firstReactive = reactiveExecutor.callTarget(
            address(automation), abi.encodeWithSelector(automation.reactiveSetPolicyActive.selector, replayJob, policyId, false)
        );
        require(firstReactive, "first reactive job should pass");
        require(!engine.isPolicyActive(policyId), "policy should be paused");

        bool secondReactive = reactiveExecutor.callTarget(
            address(automation), abi.encodeWithSelector(automation.reactiveSetPolicyActive.selector, replayJob, policyId, true)
        );
        require(!secondReactive, "replayed job should fail");
        require(!engine.isPolicyActive(policyId), "policy should remain paused after replay rejection");
    }

    function testEmergencyPauseFlow() public {
        bool outsiderPause = outsider.callTarget(
            address(automation), abi.encodeWithSelector(automation.pauseAll.selector, true)
        );
        require(!outsiderPause, "outsider should not pause");

        bool emergencyPause = emergencyActor.callTarget(
            address(automation), abi.encodeWithSelector(automation.pauseAll.selector, true)
        );
        require(emergencyPause, "emergency role should pause");
        require(engine.paused(), "engine should be paused");
        require(hook.paused(), "hook should be paused");

        SatisfyTypes.Proof[] memory proofs = new SatisfyTypes.Proof[](1);
        proofs[0] = SatisfyTypes.Proof({adapterId: WORLD_ADAPTER_ID, payload: abi.encode(WorldIdAdapter.WorldIdProofV1({
            root: 0,
            nullifierHash: 0,
            proof: _emptyProof(),
            issuedAt: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 1 days),
            signal: bytes32(0),
            externalNullifier: bytes32(0)
        }))});

        SatisfyTypes.ProofBundle memory bundle = SatisfyTypes.ProofBundle({
            proofs: proofs,
            nullifier: keccak256("pause-bundle"),
            epoch: engine.currentEpoch()
        });

        (bool pausedSwap,) = address(hook).call(
            abi.encodeWithSelector(hook.beforeSwap.selector, POOL_ID, address(0x1234), bundle)
        );
        require(!pausedSwap, "beforeSwap should fail while paused");

        bool emergencyUnpause = emergencyActor.callTarget(
            address(automation), abi.encodeWithSelector(automation.pauseAll.selector, false)
        );
        require(emergencyUnpause, "emergency role should unpause");
        require(!engine.paused(), "engine should be unpaused");
        require(!hook.paused(), "hook should be unpaused");
    }

    function testTimelockBecomesRoleAdminAndGrantsRole() public {
        AutomationCaller timelockProposer = new AutomationCaller();
        AutomationCaller timelockExecutor = new AutomationCaller();
        AutomationCaller newPolicyManager = new AutomationCaller();

        SatisfyTimelock timelock = new SatisfyTimelock(
            address(this),
            uint64(1 days),
            address(timelockProposer),
            address(timelockExecutor)
        );

        automation.setRoleAdmin(address(timelock));
        require(automation.roleAdmin() == address(timelock), "timelock should be role admin");

        bytes memory grantRoleCall = abi.encodeWithSelector(
            automation.grantRole.selector,
            automation.POLICY_MANAGER_ROLE(),
            address(newPolicyManager)
        );
        bytes32 salt = keccak256("grant-policy-manager");

        bool scheduled = timelockProposer.callTarget(
            address(timelock),
            abi.encodeWithSelector(
                timelock.schedule.selector,
                address(automation),
                uint256(0),
                grantRoleCall,
                salt,
                uint64(1 days)
            )
        );
        require(scheduled, "timelock proposal should schedule");

        bool earlyExecute = timelockExecutor.callTarget(
            address(timelock),
            abi.encodeWithSelector(timelock.execute.selector, address(automation), uint256(0), grantRoleCall, salt)
        );
        require(!earlyExecute, "execute should fail before delay");

        vm.warp(block.timestamp + 1 days + 1);

        bool executed = timelockExecutor.callTarget(
            address(timelock),
            abi.encodeWithSelector(timelock.execute.selector, address(automation), uint256(0), grantRoleCall, salt)
        );
        require(executed, "timelock execution should pass after delay");

        bool newManagerSetEpoch = newPolicyManager.callTarget(
            address(automation), abi.encodeWithSelector(automation.setEpoch.selector, uint64(3))
        );
        require(newManagerSetEpoch, "new role grantee should set epoch");
        require(engine.currentEpoch() == 3, "epoch should reflect new policy manager action");
    }

    function _as(address caller, bytes memory callData) internal {
        bool ok = AutomationCaller(caller).callTarget(address(automation), callData);
        require(ok, "call should succeed");
    }

    function _emptyProof() internal pure returns (uint256[8] memory proof) {
        return proof;
    }
}
