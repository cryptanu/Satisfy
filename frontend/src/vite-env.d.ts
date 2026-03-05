/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_RPC_URL?: string;
  readonly VITE_CHAIN_ID?: string;
  readonly VITE_POLICY_ENGINE_ADDRESS?: string;
  readonly VITE_HOOK_ADDRESS?: string;
  readonly VITE_POLICY_ID?: string;
  readonly VITE_POOL_ID?: string;
  readonly VITE_EPOCH?: string;
  readonly VITE_USER_ADDRESS?: string;
  readonly VITE_WORLD_ADAPTER_ID?: string;
  readonly VITE_WORLD_PROOF_PAYLOAD?: string;
  readonly VITE_SELF_ADAPTER_ID?: string;
  readonly VITE_SELF_PROOF_PAYLOAD?: string;
  readonly VITE_NULLIFIER?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
