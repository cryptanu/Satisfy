// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyHook} from "../src/SatisfyHook.sol";
import {SatisfyPolicyEngine} from "../src/SatisfyPolicyEngine.sol";
import {SatisfyTypes} from "../src/types/SatisfyTypes.sol";
import {SelfAdapter} from "../src/adapters/SelfAdapter.sol";
import {WorldIdAdapter} from "../src/adapters/WorldIdAdapter.sol";
import {SelfAttestationRegistry} from "../src/SelfAttestationRegistry.sol";
import {MockWorldIdVerifier} from "../src/mocks/MockWorldIdVerifier.sol";
import {ECDSA} from "../src/utils/ECDSA.sol";

interface Vm {
    function envString(string calldata key) external returns (string memory value);
    function envBytes(string calldata key) external returns (bytes memory value);
    function envAddress(string calldata key) external returns (address value);
    function warp(uint256 newTimestamp) external;
}

contract RealDataReplayTest {
    using ECDSA for bytes32;

    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant WORLD_ADAPTER_ID = keccak256("WORLD_ID");
    bytes32 private constant SELF_ADAPTER_ID = keccak256("SELF");
    bytes32 private constant POOL_ID = keccak256("REAL_DATA_POOL");

    struct FixtureData {
        address user;
        bytes worldConditionBytes;
        bytes worldProofPayload;
        bytes selfConditionBytes;
        bytes selfAttestationPayloadBytes;
        bytes selfAttestationSignature;
        bytes selfProofPayload;
    }

    struct Deployment {
        SatisfyPolicyEngine engine;
        MockWorldIdVerifier worldVerifier;
        SelfAttestationRegistry selfRegistry;
        WorldIdAdapter worldAdapter;
        SelfAdapter selfAdapter;
        SatisfyHook hook;
        uint256 policyId;
    }

    function testReplayRecordedFixturesFromEnv() public {
        if (!_fixturesEnabled()) {
            return;
        }

        FixtureData memory fixture = _loadFixture();
        Deployment memory deployed = _deployFixtureContracts(fixture.worldConditionBytes, fixture.selfConditionBytes);

        WorldIdAdapter.WorldIdProofV1 memory worldProof =
            abi.decode(fixture.worldProofPayload, (WorldIdAdapter.WorldIdProofV1));
        SelfAttestationRegistry.AttestationPayloadV1 memory selfAttestationPayload =
            abi.decode(fixture.selfAttestationPayloadBytes, (SelfAttestationRegistry.AttestationPayloadV1));

        _alignTimestamp(worldProof);
        _configureVerifiersAndRegistry(deployed, worldProof, selfAttestationPayload, fixture.selfAttestationSignature);

        SatisfyTypes.ProofBundle memory bundle = _buildBundle(
            fixture.worldProofPayload,
            fixture.selfProofPayload,
            deployed.engine.currentEpoch()
        );

        bool satisfied = deployed.engine.satisfies(deployed.policyId, fixture.user, bundle);
        require(satisfied, "recorded fixture should satisfy policy");

        bytes4 selector = deployed.hook.beforeSwap(POOL_ID, fixture.user, bundle);
        require(selector == deployed.hook.beforeSwap.selector, "hook should accept recorded fixture bundle");
    }

    function _loadFixture() internal returns (FixtureData memory fixture) {
        fixture.user = VM.envAddress("REALDATA_USER");
        fixture.worldConditionBytes = VM.envBytes("REALDATA_WORLD_CONDITION");
        fixture.worldProofPayload = VM.envBytes("REALDATA_WORLD_PROOF_PAYLOAD");
        fixture.selfConditionBytes = VM.envBytes("REALDATA_SELF_CONDITION");
        fixture.selfAttestationPayloadBytes = VM.envBytes("REALDATA_SELF_ATTESTATION_PAYLOAD");
        fixture.selfAttestationSignature = VM.envBytes("REALDATA_SELF_ATTESTATION_SIGNATURE");
        fixture.selfProofPayload = VM.envBytes("REALDATA_SELF_PROOF_PAYLOAD");
    }

    function _deployFixtureContracts(bytes memory worldConditionBytes, bytes memory selfConditionBytes)
        internal
        returns (Deployment memory deployed)
    {
        deployed.engine = new SatisfyPolicyEngine(address(this));
        deployed.worldVerifier = new MockWorldIdVerifier();
        deployed.selfRegistry = new SelfAttestationRegistry(address(this), address(0));
        deployed.worldAdapter = new WorldIdAdapter(address(this), address(deployed.worldVerifier), 1);
        deployed.selfAdapter = new SelfAdapter(address(this), address(deployed.selfRegistry));
        deployed.hook = new SatisfyHook(address(this), address(deployed.engine), address(this));

        deployed.engine.registerAdapter(WORLD_ADAPTER_ID, address(deployed.worldAdapter));
        deployed.engine.registerAdapter(SELF_ADAPTER_ID, address(deployed.selfAdapter));
        deployed.engine.setAuthorizedConsumer(address(deployed.hook), true);

        SatisfyTypes.Predicate[] memory predicates = new SatisfyTypes.Predicate[](2);
        predicates[0] = SatisfyTypes.Predicate({adapterId: WORLD_ADAPTER_ID, condition: worldConditionBytes});
        predicates[1] = SatisfyTypes.Predicate({adapterId: SELF_ADAPTER_ID, condition: selfConditionBytes});

        deployed.policyId = deployed.engine.createPolicy(SatisfyTypes.LogicOp.AND, predicates, 0, 0, true);
        deployed.hook.setPoolPolicy(POOL_ID, deployed.policyId);
    }

    function _alignTimestamp(WorldIdAdapter.WorldIdProofV1 memory worldProof) internal {
        uint256 targetTimestamp = uint256(worldProof.issuedAt) + 1;
        if (targetTimestamp > block.timestamp) {
            VM.warp(targetTimestamp);
        }
    }

    function _configureVerifiersAndRegistry(
        Deployment memory deployed,
        WorldIdAdapter.WorldIdProofV1 memory worldProof,
        SelfAttestationRegistry.AttestationPayloadV1 memory selfAttestationPayload,
        bytes memory selfAttestationSignature
    ) internal {
        deployed.worldVerifier.setValidProof(
            worldProof.root,
            deployed.worldAdapter.groupId(),
            uint256(worldProof.signal),
            worldProof.nullifierHash,
            uint256(worldProof.externalNullifier),
            worldProof.proof,
            true
        );

        bytes32 digest = deployed.selfRegistry.attestationDigest(selfAttestationPayload);
        address recoveredSigner = digest.recover(selfAttestationSignature);
        deployed.selfRegistry.setTrustedSigner(recoveredSigner, true);
        deployed.selfRegistry.submitAttestation(selfAttestationPayload, selfAttestationSignature);
    }

    function _buildBundle(bytes memory worldProofPayload, bytes memory selfProofPayload, uint64 epoch)
        internal
        pure
        returns (SatisfyTypes.ProofBundle memory)
    {
        SatisfyTypes.Proof[] memory proofs = new SatisfyTypes.Proof[](2);
        proofs[0] = SatisfyTypes.Proof({adapterId: WORLD_ADAPTER_ID, payload: worldProofPayload});
        proofs[1] = SatisfyTypes.Proof({adapterId: SELF_ADAPTER_ID, payload: selfProofPayload});

        return SatisfyTypes.ProofBundle({proofs: proofs, nullifier: keccak256("real-data-fixture"), epoch: epoch});
    }

    function _fixturesEnabled() internal returns (bool) {
        (bool ok, bytes memory raw) =
            address(VM).call(abi.encodeWithSignature("envString(string)", "REALDATA_FIXTURES_ENABLED"));
        if (!ok) {
            return false;
        }

        string memory enabled = abi.decode(raw, (string));
        return keccak256(bytes(enabled)) == keccak256(bytes("true"));
    }
}
