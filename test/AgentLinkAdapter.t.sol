// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentLinkAdapter} from "../src/adapters/AgentLinkAdapter.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 newTimestamp) external;
}

contract AgentLinkAdapterTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant SIGNER_PK = 0xA11CE;

    address private constant USER = address(0x1234);

    AgentLinkAdapter internal adapter;
    bytes32 internal sourceBridgeId;
    bytes32 internal policyContext;

    function setUp() public {
        adapter = new AgentLinkAdapter(address(this), vm.addr(SIGNER_PK));
        sourceBridgeId = keccak256("AGENTKIT_WORLD_V1");
        policyContext = keccak256("AGENT_POLICY_CTX_V1");
    }

    function testVerifyWithContextValidProof() public {
        uint64 epoch = 3;
        uint256 policyId = 9;
        bytes memory conditionBytes = abi.encode(
            AgentLinkAdapter.AgentLinkConditionV1({
                requireLinkedHuman: true,
                policyContext: policyContext,
                maxProofAge: uint64(1 days),
                requiredSourceBridgeId: sourceBridgeId
            })
        );

        bytes memory payload = _buildPayload(USER, policyId, epoch, conditionBytes, uint64(block.timestamp), uint64(block.timestamp + 1 days), 0);
        bytes32 nullifier = _expectedNullifier(policyId, epoch, conditionBytes, payload);

        bool ok = adapter.verifyWithContext(USER, payload, conditionBytes, nullifier, epoch, policyId);
        require(ok, "valid proof should verify");
    }

    function testVerifyWithContextRejectsWrongNullifier() public {
        uint64 epoch = 1;
        uint256 policyId = 10;
        bytes memory conditionBytes = abi.encode(
            AgentLinkAdapter.AgentLinkConditionV1({
                requireLinkedHuman: true,
                policyContext: policyContext,
                maxProofAge: uint64(1 days),
                requiredSourceBridgeId: sourceBridgeId
            })
        );

        bytes memory payload = _buildPayload(USER, policyId, epoch, conditionBytes, uint64(block.timestamp), uint64(block.timestamp + 1 days), 1);
        bool ok = adapter.verifyWithContext(USER, payload, conditionBytes, bytes32("wrong"), epoch, policyId);
        require(!ok, "wrong nullifier should fail");
    }

    function testVerifyWithoutContextFailsWhenHumanRequired() public {
        uint64 epoch = 1;
        uint256 policyId = 11;
        bytes memory conditionBytes = abi.encode(
            AgentLinkAdapter.AgentLinkConditionV1({
                requireLinkedHuman: true,
                policyContext: policyContext,
                maxProofAge: uint64(1 days),
                requiredSourceBridgeId: sourceBridgeId
            })
        );

        bytes memory payload = _buildPayload(USER, policyId, epoch, conditionBytes, uint64(block.timestamp), uint64(block.timestamp + 1 days), 2);
        bool ok = adapter.verify(USER, payload, conditionBytes);
        require(!ok, "legacy verify path should fail for strict context checks");
    }

    function testVerifyWithContextRejectsExpiredOrStaleProof() public {
        uint64 epoch = 5;
        uint256 policyId = 12;
        bytes memory conditionBytes = abi.encode(
            AgentLinkAdapter.AgentLinkConditionV1({
                requireLinkedHuman: true,
                policyContext: policyContext,
                maxProofAge: uint64(1 hours),
                requiredSourceBridgeId: sourceBridgeId
            })
        );

        bytes memory payload = _buildPayload(USER, policyId, epoch, conditionBytes, uint64(1 days), uint64(2 days), 3);
        bytes32 nullifier = _expectedNullifier(policyId, epoch, conditionBytes, payload);
        vm.warp(10 days);

        bool ok = adapter.verifyWithContext(USER, payload, conditionBytes, nullifier, epoch, policyId);
        require(!ok, "expired or stale proof should fail");
    }

    function testVerifyWithContextRejectsWrongSourceBridge() public {
        uint64 epoch = 2;
        uint256 policyId = 13;

        bytes memory conditionBytes = abi.encode(
            AgentLinkAdapter.AgentLinkConditionV1({
                requireLinkedHuman: true,
                policyContext: policyContext,
                maxProofAge: uint64(1 days),
                requiredSourceBridgeId: keccak256("DIFFERENT_BRIDGE")
            })
        );

        bytes memory payload = _buildPayload(USER, policyId, epoch, conditionBytes, uint64(block.timestamp), uint64(block.timestamp + 1 days), 4);
        bytes32 nullifier = _expectedNullifier(policyId, epoch, conditionBytes, payload);
        bool ok = adapter.verifyWithContext(USER, payload, conditionBytes, nullifier, epoch, policyId);
        require(!ok, "source bridge mismatch should fail");
    }

    function _buildPayload(
        address user,
        uint256 policyId,
        uint64 epoch,
        bytes memory conditionBytes,
        uint64 issuedAt,
        uint64 validUntil,
        uint256 relayNonce
    ) internal returns (bytes memory) {
        AgentLinkAdapter.AgentLinkConditionV1 memory condition =
            abi.decode(conditionBytes, (AgentLinkAdapter.AgentLinkConditionV1));
        bytes32 humanIdHash = keccak256(abi.encodePacked("human", user, relayNonce));
        bytes32 nullifier = keccak256(abi.encode(policyId, epoch, humanIdHash, condition.policyContext));

        bytes32 digest = adapter.proofDigest(
            user,
            policyId,
            epoch,
            nullifier,
            humanIdHash,
            issuedAt,
            validUntil,
            relayNonce,
            condition.policyContext,
            sourceBridgeId
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        return abi.encode(
            AgentLinkAdapter.AgentLinkProofV1({
                humanIdHash: humanIdHash,
                issuedAt: issuedAt,
                validUntil: validUntil,
                relayNonce: relayNonce,
                sourceBridgeId: sourceBridgeId,
                signature: signature
            })
        );
    }

    function _expectedNullifier(uint256 policyId, uint64 epoch, bytes memory conditionBytes, bytes memory payload)
        internal
        pure
        returns (bytes32)
    {
        AgentLinkAdapter.AgentLinkConditionV1 memory condition =
            abi.decode(conditionBytes, (AgentLinkAdapter.AgentLinkConditionV1));
        AgentLinkAdapter.AgentLinkProofV1 memory proof = abi.decode(payload, (AgentLinkAdapter.AgentLinkProofV1));
        return keccak256(abi.encode(policyId, epoch, proof.humanIdHash, condition.policyContext));
    }
}
