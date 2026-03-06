export const networkModeOptions = [
  {value: 'unichain-sepolia', label: 'Unichain Sepolia'},
  {value: 'unichain-mainnet', label: 'Unichain Mainnet'},
  {value: 'custom', label: 'Custom RPC'},
] as const;

export type NetworkMode = (typeof networkModeOptions)[number]['value'];

type NetworkDefaults = {
  policyEngineAddress?: string;
  hookAddress?: string;
  policyId?: string;
  poolId?: string;
  epoch?: string;
  userAddress?: string;
  worldAdapterId?: string;
  selfAdapterId?: string;
};

export type NetworkPreset = {
  label: string;
  chainId: string;
  rpcUrl: string;
  explorerBaseUrl: string;
  defaults: NetworkDefaults;
};

const MAINNET_CHAIN_ID = '130';
const SEPOLIA_CHAIN_ID = '1301';

const MAINNET_EXPLORER = 'https://uniscan.xyz';
const SEPOLIA_EXPLORER = 'https://sepolia.uniscan.xyz';

const MAINNET_RPC_DEFAULT = 'https://mainnet.unichain.org';
const SEPOLIA_RPC_DEFAULT = 'https://sepolia.unichain.org';

export function getDefaultNetworkMode(env: ImportMetaEnv): NetworkMode {
  const configured = (env.VITE_DEFAULT_NETWORK ?? 'unichain-sepolia').toLowerCase();
  const valid = new Set(networkModeOptions.map((option) => option.value));
  return valid.has(configured as NetworkMode) ? (configured as NetworkMode) : 'unichain-sepolia';
}

export function getNetworkPreset(mode: Exclude<NetworkMode, 'custom'>, env: ImportMetaEnv): NetworkPreset {
  if (mode === 'unichain-mainnet') {
    return {
      label: 'Unichain Mainnet',
      chainId: MAINNET_CHAIN_ID,
      rpcUrl: env.VITE_UNICHAIN_MAINNET_RPC_URL ?? MAINNET_RPC_DEFAULT,
      explorerBaseUrl: MAINNET_EXPLORER,
      defaults: {
        policyEngineAddress: env.VITE_UNICHAIN_MAINNET_POLICY_ENGINE_ADDRESS,
        hookAddress: env.VITE_UNICHAIN_MAINNET_HOOK_ADDRESS,
        policyId: env.VITE_UNICHAIN_MAINNET_POLICY_ID,
        poolId: env.VITE_UNICHAIN_MAINNET_POOL_ID,
        epoch: env.VITE_UNICHAIN_MAINNET_EPOCH,
        userAddress: env.VITE_UNICHAIN_MAINNET_USER_ADDRESS,
        worldAdapterId: env.VITE_UNICHAIN_MAINNET_WORLD_ADAPTER_ID,
        selfAdapterId: env.VITE_UNICHAIN_MAINNET_SELF_ADAPTER_ID,
      },
    };
  }

  return {
    label: 'Unichain Sepolia',
    chainId: SEPOLIA_CHAIN_ID,
    rpcUrl: env.VITE_UNICHAIN_SEPOLIA_RPC_URL ?? SEPOLIA_RPC_DEFAULT,
    explorerBaseUrl: SEPOLIA_EXPLORER,
    defaults: {
      policyEngineAddress: env.VITE_UNICHAIN_SEPOLIA_POLICY_ENGINE_ADDRESS,
      hookAddress: env.VITE_UNICHAIN_SEPOLIA_HOOK_ADDRESS,
      policyId: env.VITE_UNICHAIN_SEPOLIA_POLICY_ID,
      poolId: env.VITE_UNICHAIN_SEPOLIA_POOL_ID,
      epoch: env.VITE_UNICHAIN_SEPOLIA_EPOCH,
      userAddress: env.VITE_UNICHAIN_SEPOLIA_USER_ADDRESS,
      worldAdapterId: env.VITE_UNICHAIN_SEPOLIA_WORLD_ADAPTER_ID,
      selfAdapterId: env.VITE_UNICHAIN_SEPOLIA_SELF_ADAPTER_ID,
    },
  };
}

export function getExplorerBaseUrl(chainId: number): string | null {
  if (chainId === Number(MAINNET_CHAIN_ID)) {
    return MAINNET_EXPLORER;
  }
  if (chainId === Number(SEPOLIA_CHAIN_ID)) {
    return SEPOLIA_EXPLORER;
  }
  return null;
}

export function getChainName(chainId: number): string {
  if (chainId === Number(MAINNET_CHAIN_ID)) {
    return 'Unichain Mainnet';
  }
  if (chainId === Number(SEPOLIA_CHAIN_ID)) {
    return 'Unichain Sepolia';
  }
  return `Satisfy Chain ${chainId}`;
}
