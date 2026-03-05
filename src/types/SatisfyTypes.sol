// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library SatisfyTypes {
    enum LogicOp {
        AND,
        OR
    }

    struct Predicate {
        bytes32 adapterId;
        bytes condition;
    }

    struct Proof {
        bytes32 adapterId;
        bytes payload;
    }

    struct ProofBundle {
        Proof[] proofs;
        bytes32 nullifier;
        uint64 epoch;
    }
}
