// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyReactiveCallbackReceiver} from "../src/reactive/SatisfyReactiveCallbackReceiver.sol";

contract MockReactiveGatewayDispatch {
    uint8 public constant ACTION_SET_EPOCH = 0;
    uint8 public constant ACTION_PAUSE_ALL = 8;

    uint256 public callCount;
    bytes32 public lastJobId;
    uint8 public lastAction;
    bytes public lastPayload;

    function executeFromReactiveCallback(bytes32 jobId, uint8 action, bytes calldata payload) external {
        callCount += 1;
        lastJobId = jobId;
        lastAction = action;
        lastPayload = payload;
    }
}

contract MockReactivePolicyEngineState {
    uint64 public currentEpoch = 1;
    bool public paused;

    function setEpoch(uint64 newEpoch) external {
        currentEpoch = newEpoch;
    }

    function setPaused(bool value) external {
        paused = value;
    }
}

contract ExternalCaller {
    function callHandleRevocation(address target, address rvmId, bytes32 jobId) external returns (bool) {
        (bool ok,) = target.call(
            abi.encodeWithSignature("handleRevocation(address,bytes32)", rvmId, jobId)
        );
        return ok;
    }
}

contract SatisfyReactiveCallbackReceiverTest {
    SatisfyReactiveCallbackReceiver internal receiver;
    MockReactiveGatewayDispatch internal gateway;
    MockReactivePolicyEngineState internal policy;

    address internal constant REACTIVE_OWNER = address(0xA11CE);

    function setUp() public {
        gateway = new MockReactiveGatewayDispatch();
        policy = new MockReactivePolicyEngineState();
        receiver =
            new SatisfyReactiveCallbackReceiver(address(this), address(this), REACTIVE_OWNER, address(gateway), address(policy));
    }

    function testHandleRevocationDispatchesSetEpoch() public {
        bytes32 jobId = keccak256("revocation-job");
        receiver.handleRevocation(REACTIVE_OWNER, jobId);

        require(gateway.callCount() == 1, "gateway should be called");
        require(gateway.lastJobId() == jobId, "job id mismatch");
        require(gateway.lastAction() == gateway.ACTION_SET_EPOCH(), "action mismatch");
        uint64 nextEpoch = abi.decode(gateway.lastPayload(), (uint64));
        require(nextEpoch == 2, "next epoch mismatch");
    }

    function testHandleSignerDisableDispatchesPause() public {
        bytes32 jobId = keccak256("signer-disable-job");
        receiver.handleSignerDisable(REACTIVE_OWNER, jobId);

        require(gateway.callCount() == 1, "gateway should be called");
        require(gateway.lastAction() == gateway.ACTION_PAUSE_ALL(), "action mismatch");
        bool pauseValue = abi.decode(gateway.lastPayload(), (bool));
        require(pauseValue, "pause value mismatch");
    }

    function testHandleSignerDisableSkipsWhenAlreadyPaused() public {
        policy.setPaused(true);
        bytes32 jobId = keccak256("signer-disable-paused");
        receiver.handleSignerDisable(REACTIVE_OWNER, jobId);
        require(gateway.callCount() == 0, "gateway should not be called when already paused");
    }

    function testRejectsUnauthorizedSender() public {
        ExternalCaller caller = new ExternalCaller();
        bool ok = caller.callHandleRevocation(address(receiver), REACTIVE_OWNER, keccak256("unauthorized"));
        require(!ok, "unauthorized sender should fail");
    }

    function testRejectsUnexpectedReactiveOwner() public {
        (bool ok,) = address(receiver).call(
            abi.encodeWithSignature("handleRevocation(address,bytes32)", address(0xB0B), keccak256("wrong-owner"))
        );
        require(!ok, "wrong reactive owner should fail");
    }
}
