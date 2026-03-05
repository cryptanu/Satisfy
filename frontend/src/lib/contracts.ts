export const policyEngineAbi = [
  {
    type: 'function',
    name: 'satisfies',
    stateMutability: 'view',
    inputs: [
      {name: 'policyId', type: 'uint256'},
      {name: 'user', type: 'address'},
      {
        name: 'bundle',
        type: 'tuple',
        components: [
          {
            name: 'proofs',
            type: 'tuple[]',
            components: [
              {name: 'adapterId', type: 'bytes32'},
              {name: 'payload', type: 'bytes'},
            ],
          },
          {name: 'nullifier', type: 'bytes32'},
          {name: 'epoch', type: 'uint64'},
        ],
      },
    ],
    outputs: [{name: '', type: 'bool'}],
  },
] as const;

export const satisfyHookAbi = [
  {
    type: 'function',
    name: 'beforeSwap',
    stateMutability: 'nonpayable',
    inputs: [
      {name: 'poolId', type: 'bytes32'},
      {name: 'sender', type: 'address'},
      {
        name: 'bundle',
        type: 'tuple',
        components: [
          {
            name: 'proofs',
            type: 'tuple[]',
            components: [
              {name: 'adapterId', type: 'bytes32'},
              {name: 'payload', type: 'bytes'},
            ],
          },
          {name: 'nullifier', type: 'bytes32'},
          {name: 'epoch', type: 'uint64'},
        ],
      },
    ],
    outputs: [{name: '', type: 'bytes4'}],
  },
] as const;

export type ProofInput = {
  adapterId: `0x${string}`;
  payload: `0x${string}`;
};

export type ProofBundleInput = {
  proofs: ProofInput[];
  nullifier: `0x${string}`;
  epoch: bigint;
};
