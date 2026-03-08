/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_DEFAULT_NETWORK?: string;

  readonly VITE_RPC_URL?: string;
  readonly VITE_CHAIN_ID?: string;

  readonly VITE_POLICY_ENGINE_ADDRESS?: string;
  readonly VITE_HOOK_ADDRESS?: string;
  readonly VITE_POLICY_ID?: string;
  readonly VITE_POOL_ID?: string;
  readonly VITE_EPOCH?: string;
  readonly VITE_USER_ADDRESS?: string;

  readonly VITE_UNICHAIN_MAINNET_RPC_URL?: string;
  readonly VITE_UNICHAIN_SEPOLIA_RPC_URL?: string;

  readonly VITE_UNICHAIN_MAINNET_POLICY_ENGINE_ADDRESS?: string;
  readonly VITE_UNICHAIN_MAINNET_HOOK_ADDRESS?: string;
  readonly VITE_UNICHAIN_MAINNET_POLICY_ID?: string;
  readonly VITE_UNICHAIN_MAINNET_POOL_ID?: string;
  readonly VITE_UNICHAIN_MAINNET_EPOCH?: string;
  readonly VITE_UNICHAIN_MAINNET_AUTOMATION_MODULE_ADDRESS?: string;
  readonly VITE_UNICHAIN_MAINNET_USER_ADDRESS?: string;
  readonly VITE_UNICHAIN_MAINNET_WORLD_ADAPTER_ID?: string;
  readonly VITE_UNICHAIN_MAINNET_SELF_ADAPTER_ID?: string;
  readonly VITE_UNICHAIN_MAINNET_DEPLOYMENT_ARTIFACT?: string;

  readonly VITE_UNICHAIN_SEPOLIA_POLICY_ENGINE_ADDRESS?: string;
  readonly VITE_UNICHAIN_SEPOLIA_HOOK_ADDRESS?: string;
  readonly VITE_UNICHAIN_SEPOLIA_POLICY_ID?: string;
  readonly VITE_UNICHAIN_SEPOLIA_POOL_ID?: string;
  readonly VITE_UNICHAIN_SEPOLIA_EPOCH?: string;
  readonly VITE_UNICHAIN_SEPOLIA_AUTOMATION_MODULE_ADDRESS?: string;
  readonly VITE_UNICHAIN_SEPOLIA_USER_ADDRESS?: string;
  readonly VITE_UNICHAIN_SEPOLIA_WORLD_ADAPTER_ID?: string;
  readonly VITE_UNICHAIN_SEPOLIA_SELF_ADAPTER_ID?: string;
  readonly VITE_UNICHAIN_SEPOLIA_DEPLOYMENT_ARTIFACT?: string;

  readonly VITE_WORLD_ADAPTER_ID?: string;
  readonly VITE_WORLD_PROOF_PAYLOAD?: string;
  readonly VITE_SELF_ADAPTER_ID?: string;
  readonly VITE_SELF_PROOF_PAYLOAD?: string;
  readonly VITE_NULLIFIER?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
