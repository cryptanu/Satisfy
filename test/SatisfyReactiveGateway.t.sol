// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyAutomationModule} from "../src/SatisfyAutomationModule.sol";
import {SatisfyHook} from "../src/SatisfyHook.sol";
import {SatisfyPolicyEngine} from "../src/SatisfyPolicyEngine.sol";
import {SatisfyReactiveGateway} from "../src/SatisfyReactiveGateway.sol";
import {SelfAdapter} from "../src/adapters/SelfAdapter.sol";
import {WorldIdAdapter} from "../src/adapters/WorldIdAdapter.sol";
import {SelfAttestationRegistry} from "../src/SelfAttestationRegistry.sol";
import {MockWorldIdVerifier} from "../src/mocks/MockWorldIdVerifier.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract SatisfyReactiveGatewayTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant WORKER_PK = 0xA11CE;
    uint256 private constant OTHER_PK = 0xB0B;

    SatisfyPolicyEngine internal engine;
    SatisfyHook internal hook;
    WorldIdAdapter internal worldAdapter;
    SelfAdapter internal selfAdapter;
    SelfAttestationRegistry internal selfRegistry;
    MockWorldIdVerifier internal worldVerifier;
    SatisfyReactiveGateway internal gateway;
    SatisfyAutomationModule internal automation;

    function setUp() public {
        engine = new SatisfyPolicyEngine(address(this));
        worldVerifier = new MockWorldIdVerifier();
        selfRegistry = new SelfAttestationRegistry(address(this), vm.addr(WORKER_PK));
        worldAdapter = new WorldIdAdapter(address(this), address(worldVerifier), 1);
        selfAdapter = new SelfAdapter(address(this), address(selfRegistry));
        hook = new SatisfyHook(address(this), address(engine), address(this));

        gateway = new SatisfyReactiveGateway(address(this), address(0), vm.addr(WORKER_PK));

        automation = new SatisfyAutomationModule(
            address(this),
            address(this),
            address(this),
            address(this),
            address(this),
            address(gateway),
            address(this),
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

        gateway.setAutomationModule(address(automation));
    }

    function testSignedSetEpochExecutesOnChain() public {
        bytes memory payload = abi.encode(uint64(2));
        SatisfyReactiveGateway.JobV1 memory job = SatisfyReactiveGateway.JobV1({
            jobId: keccak256("gateway-set-epoch"),
            action: gateway.ACTION_SET_EPOCH(),
            payload: payload,
            validUntil: uint64(block.timestamp + 1 days),
            nonce: 0
        });

        bytes memory sig = _signJob(job, WORKER_PK);
        gateway.execute(job, sig);

        require(engine.currentEpoch() == 2, "epoch should update via gateway");
    }

    function testSignedPauseExecutesOnChain() public {
        bytes memory payload = abi.encode(true);
        SatisfyReactiveGateway.JobV1 memory job = SatisfyReactiveGateway.JobV1({
            jobId: keccak256("gateway-pause"),
            action: gateway.ACTION_PAUSE_ALL(),
            payload: payload,
            validUntil: uint64(block.timestamp + 1 days),
            nonce: 0
        });

        bytes memory sig = _signJob(job, WORKER_PK);
        gateway.execute(job, sig);

        require(engine.paused(), "engine should be paused");
        require(hook.paused(), "hook should be paused");
    }

    function testReplayAndNonceProtection() public {
        bytes memory payload = abi.encode(uint64(2));
        SatisfyReactiveGateway.JobV1 memory job = SatisfyReactiveGateway.JobV1({
            jobId: keccak256("gateway-replay"),
            action: gateway.ACTION_SET_EPOCH(),
            payload: payload,
            validUntil: uint64(block.timestamp + 1 days),
            nonce: 0
        });

        bytes memory sig = _signJob(job, WORKER_PK);
        gateway.execute(job, sig);

        (bool replayOk,) = address(gateway).call(abi.encodeWithSelector(gateway.execute.selector, job, sig));
        require(!replayOk, "replay should fail");

        SatisfyReactiveGateway.JobV1 memory badNonceJob = SatisfyReactiveGateway.JobV1({
            jobId: keccak256("gateway-bad-nonce"),
            action: gateway.ACTION_SET_EPOCH(),
            payload: abi.encode(uint64(3)),
            validUntil: uint64(block.timestamp + 1 days),
            nonce: 0
        });
        bytes memory badNonceSig = _signJob(badNonceJob, WORKER_PK);
        (bool nonceOk,) =
            address(gateway).call(abi.encodeWithSelector(gateway.execute.selector, badNonceJob, badNonceSig));
        require(!nonceOk, "stale nonce should fail");
    }

    function testRejectsUntrustedWorkerSignature() public {
        bytes memory payload = abi.encode(uint64(2));
        SatisfyReactiveGateway.JobV1 memory job = SatisfyReactiveGateway.JobV1({
            jobId: keccak256("gateway-untrusted"),
            action: gateway.ACTION_SET_EPOCH(),
            payload: payload,
            validUntil: uint64(block.timestamp + 1 days),
            nonce: 0
        });

        bytes memory sig = _signJob(job, OTHER_PK);
        (bool ok,) = address(gateway).call(abi.encodeWithSelector(gateway.execute.selector, job, sig));
        require(!ok, "untrusted worker should fail");
    }

    function testReactiveCallbackRequiresAuthorization() public {
        bytes32 jobId = keccak256("callback-unauthorized");
        bytes memory payload = abi.encode(uint64(2));

        (bool ok,) = address(gateway).call(
            abi.encodeWithSelector(
                gateway.executeFromReactiveCallback.selector, jobId, gateway.ACTION_SET_EPOCH(), payload
            )
        );
        require(!ok, "unauthorized callback should fail");
    }

    function testAuthorizedReactiveCallbackExecutesAndRejectsReplay() public {
        bytes32 jobId = keccak256("callback-authorized");
        bytes memory payload = abi.encode(uint64(2));

        gateway.setReactiveCallback(address(this), true);
        gateway.executeFromReactiveCallback(jobId, gateway.ACTION_SET_EPOCH(), payload);

        require(engine.currentEpoch() == 2, "authorized callback should rotate epoch");

        (bool replayOk,) = address(gateway).call(
            abi.encodeWithSelector(
                gateway.executeFromReactiveCallback.selector, jobId, gateway.ACTION_SET_EPOCH(), payload
            )
        );
        require(!replayOk, "callback replay should fail");
    }

    function _signJob(SatisfyReactiveGateway.JobV1 memory job, uint256 privateKey) internal returns (bytes memory) {
        bytes32 digest = gateway.jobDigest(job);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
