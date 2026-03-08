import {useEffect, useMemo, useState} from 'react';
import {motion} from 'motion/react';
import {
  ArrowRight,
  CheckCircle2,
  Fingerprint,
  LoaderCircle,
  Network,
  Plus,
  Send,
  Shield,
  Terminal,
  Trash2,
  Wallet,
} from 'lucide-react';
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  http,
  type Address,
  type EIP1193Provider,
  type Hex,
} from 'viem';
import {policyEngineAbi, satisfyHookAbi, type ProofBundleInput} from './lib/contracts';
import {
  validateSelfAttestationProofPayload,
  validateWorldIdProofPayload,
} from './lib/proofSchemas';
import {
  getChainName,
  getDefaultNetworkMode,
  getExplorerBaseUrl,
  getNetworkPreset,
  networkModeOptions,
  type NetworkMode,
} from './lib/unichain';

declare global {
  interface Window {
    ethereum?: EIP1193Provider;
  }
}

type ProofDraft = {
  adapterId: string;
  payload: string;
};

type StatusTone = 'neutral' | 'success' | 'error';

type BusyAction = 'connect' | 'switch' | 'read' | 'write' | null;

type DeploymentArtifact = {
  policyEngine?: string;
  hook?: string;
  policyId?: string | number;
  poolId?: string;
  epoch?: string | number;
  worldAdapterId?: string;
  selfAdapterId?: string;
};

const env = import.meta.env;
const defaultNetworkMode = getDefaultNetworkMode(env);
const defaultPreset =
  defaultNetworkMode === 'custom' ? null : getNetworkPreset(defaultNetworkMode, env);

const CodeBlock = ({code}: {code: string}) => (
  <div className="bg-black/50 border border-white/10 rounded-lg p-4 font-mono text-sm text-gray-300 overflow-x-auto">
    <pre>
      <code>{code}</code>
    </pre>
  </div>
);

function randomHex32(): Hex {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return `0x${Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}

function normalizeHex(value: string, label: string, expectedBytes?: number): Hex {
  const normalized = value.trim().toLowerCase();
  if (!normalized.startsWith('0x')) {
    throw new Error(`${label} must start with 0x`);
  }
  if (!/^0x[0-9a-f]*$/.test(normalized)) {
    throw new Error(`${label} must be valid hex`);
  }
  if ((normalized.length - 2) % 2 !== 0) {
    throw new Error(`${label} must have an even number of hex chars`);
  }
  if (expectedBytes && normalized.length !== 2 + expectedBytes * 2) {
    throw new Error(`${label} must be exactly ${expectedBytes} bytes`);
  }
  return normalized as Hex;
}

function normalizeAddress(value: string, label: string): Address {
  const normalized = value.trim();
  if (!/^0x[a-fA-F0-9]{40}$/.test(normalized)) {
    throw new Error(`${label} must be a valid 20-byte address`);
  }
  return normalized as Address;
}

function parseUint(value: string, label: string): bigint {
  const trimmed = value.trim();
  if (!/^\d+$/.test(trimmed)) {
    throw new Error(`${label} must be a non-negative integer`);
  }
  return BigInt(trimmed);
}

function parseChainId(value: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error('CHAIN_ID must be a positive integer');
  }
  return parsed;
}

function artifactUrlFromEnv(value: string): string {
  const trimmed = value.trim();
  if (trimmed === '') {
    throw new Error('Deployment artifact path is empty');
  }

  if (trimmed.startsWith('/deployments/')) {
    return trimmed;
  }

  if (trimmed.startsWith('/')) {
    return `/@fs${trimmed}`;
  }

  return trimmed;
}

export default function App() {
  const [networkMode, setNetworkMode] =
    useState<NetworkMode>(defaultNetworkMode);

  const [rpcUrl, setRpcUrl] = useState(
    defaultPreset?.rpcUrl ?? env.VITE_RPC_URL ?? 'http://127.0.0.1:8545',
  );
  const [chainId, setChainId] = useState(
    defaultPreset?.chainId ?? env.VITE_CHAIN_ID ?? '31337',
  );

  const [policyEngineAddress, setPolicyEngineAddress] = useState(
    defaultPreset?.defaults.policyEngineAddress ?? env.VITE_POLICY_ENGINE_ADDRESS ?? '',
  );
  const [hookAddress, setHookAddress] = useState(
    defaultPreset?.defaults.hookAddress ?? env.VITE_HOOK_ADDRESS ?? '',
  );
  const [policyId, setPolicyId] = useState(
    defaultPreset?.defaults.policyId ?? env.VITE_POLICY_ID ?? '1',
  );
  const [poolId, setPoolId] = useState(
    defaultPreset?.defaults.poolId ?? env.VITE_POOL_ID ?? '',
  );
  const [epoch, setEpoch] = useState(
    defaultPreset?.defaults.epoch ?? env.VITE_EPOCH ?? '1',
  );
  const [userAddress, setUserAddress] = useState(
    defaultPreset?.defaults.userAddress ?? env.VITE_USER_ADDRESS ?? '',
  );

  const [nullifier, setNullifier] = useState<Hex>(
    (env.VITE_NULLIFIER as Hex) ?? randomHex32(),
  );
  const [proofs, setProofs] = useState<ProofDraft[]>([
    {
      adapterId:
        defaultPreset?.defaults.worldAdapterId ??
        env.VITE_WORLD_ADAPTER_ID ??
        '',
      payload: env.VITE_WORLD_PROOF_PAYLOAD ?? '0x',
    },
    {
      adapterId:
        defaultPreset?.defaults.selfAdapterId ??
        env.VITE_SELF_ADAPTER_ID ??
        '',
      payload: env.VITE_SELF_PROOF_PAYLOAD ?? '0x',
    },
  ]);

  const [walletAddress, setWalletAddress] = useState('');
  const [statusMessage, setStatusMessage] = useState(
    'Ready. Configure contracts and test a proof bundle.',
  );
  const [statusTone, setStatusTone] = useState<StatusTone>('neutral');
  const [txHash, setTxHash] = useState('');
  const [busyAction, setBusyAction] = useState<BusyAction>(null);

  const parsedChainId = useMemo(() => {
    try {
      return parseChainId(chainId);
    } catch {
      return null;
    }
  }, [chainId]);

  const explorerBaseUrl = useMemo(() => {
    if (!parsedChainId) {
      return null;
    }
    return getExplorerBaseUrl(parsedChainId);
  }, [parsedChainId]);

  const txExplorerUrl =
    txHash && explorerBaseUrl
      ? `${explorerBaseUrl.replace(/\/$/, '')}/tx/${txHash}`
      : '';

  const knownWorldAdapterIds = useMemo(() => {
    const known = [
      env.VITE_WORLD_ADAPTER_ID,
      env.VITE_UNICHAIN_SEPOLIA_WORLD_ADAPTER_ID,
      env.VITE_UNICHAIN_MAINNET_WORLD_ADAPTER_ID,
      defaultPreset?.defaults.worldAdapterId,
    ]
      .filter((value): value is string => Boolean(value))
      .map((value) => value.toLowerCase());
    return new Set(known);
  }, []);

  const knownSelfAdapterIds = useMemo(() => {
    const known = [
      env.VITE_SELF_ADAPTER_ID,
      env.VITE_UNICHAIN_SEPOLIA_SELF_ADAPTER_ID,
      env.VITE_UNICHAIN_MAINNET_SELF_ADAPTER_ID,
      defaultPreset?.defaults.selfAdapterId,
    ]
      .filter((value): value is string => Boolean(value))
      .map((value) => value.toLowerCase());
    return new Set(known);
  }, []);

  const chain = useMemo(() => {
    const activeChainId = parseChainId(chainId);
    return defineChain({
      id: activeChainId,
      name: getChainName(activeChainId),
      nativeCurrency: {name: 'Ether', symbol: 'ETH', decimals: 18},
      rpcUrls: {
        default: {http: [rpcUrl]},
      },
    });
  }, [chainId, rpcUrl]);

  const publicClient = useMemo(
    () =>
      createPublicClient({
        chain,
        transport: http(rpcUrl),
      }),
    [chain, rpcUrl],
  );

  const setSuccess = (message: string) => {
    setStatusTone('success');
    setStatusMessage(message);
  };

  const setError = (message: string) => {
    setStatusTone('error');
    setStatusMessage(message);
  };

  const applyDeploymentArtifact = async (
    artifactLocation: string | undefined,
    label: string,
  ) => {
    if (!artifactLocation) {
      return false;
    }

    try {
      const response = await fetch(artifactUrlFromEnv(artifactLocation), {
        cache: 'no-store',
      });
      if (!response.ok) {
        throw new Error(`Artifact fetch failed (${response.status})`);
      }

      const artifact = (await response.json()) as DeploymentArtifact;

      if (artifact.policyEngine) {
        setPolicyEngineAddress(artifact.policyEngine);
      }
      if (artifact.hook) {
        setHookAddress(artifact.hook);
      }
      if (artifact.policyId !== undefined) {
        setPolicyId(String(artifact.policyId));
      }
      if (artifact.poolId) {
        setPoolId(artifact.poolId);
      }
      if (artifact.epoch !== undefined) {
        setEpoch(String(artifact.epoch));
      }

      setProofs((current) => {
        const next = [...current];
        if (next[0] && artifact.worldAdapterId) {
          next[0] = {...next[0], adapterId: artifact.worldAdapterId};
        }
        if (next[1] && artifact.selfAdapterId) {
          next[1] = {...next[1], adapterId: artifact.selfAdapterId};
        }
        return next;
      });

      setSuccess(`Loaded ${label} defaults from deployment artifact.`);
      return true;
    } catch (error) {
      setError(
        error instanceof Error
          ? `Failed to load deployment artifact: ${error.message}`
          : 'Failed to load deployment artifact',
      );
      return false;
    }
  };

  const applyNetworkMode = (nextMode: NetworkMode) => {
    setNetworkMode(nextMode);

    if (nextMode === 'custom') {
      setSuccess('Switched to custom network mode.');
      return;
    }

    const preset = getNetworkPreset(nextMode, env);
    setRpcUrl(preset.rpcUrl);
    setChainId(preset.chainId);
    setPolicyEngineAddress(preset.defaults.policyEngineAddress ?? '');
    setHookAddress(preset.defaults.hookAddress ?? '');
    setPolicyId(preset.defaults.policyId ?? '1');
    setPoolId(preset.defaults.poolId ?? '');
    setEpoch(preset.defaults.epoch ?? '1');

    if (!walletAddress) {
      setUserAddress(preset.defaults.userAddress ?? '');
    }

    setProofs((current) => {
      const next = [...current];
      if (next[0]) {
        next[0] = {
          ...next[0],
          adapterId: preset.defaults.worldAdapterId ?? next[0].adapterId,
        };
      }
      if (next[1]) {
        next[1] = {
          ...next[1],
          adapterId: preset.defaults.selfAdapterId ?? next[1].adapterId,
        };
      }
      return next;
    });

    void applyDeploymentArtifact(
      preset.defaults.deploymentArtifact,
      preset.label,
    ).then((loaded) => {
      if (!loaded) {
        setSuccess(`Loaded ${preset.label} defaults.`);
      }
    });
  };

  useEffect(() => {
    if (!defaultPreset?.defaults.deploymentArtifact) {
      return;
    }

    void applyDeploymentArtifact(
      defaultPreset.defaults.deploymentArtifact,
      defaultPreset.label,
    );
  }, []);

  const buildBundle = (): ProofBundleInput => {
    const parsedProofs = proofs
      .filter(
        (proof) => proof.adapterId.trim() !== '' || proof.payload.trim() !== '',
      )
      .map((proof, index) => {
        if (!proof.adapterId.trim() || !proof.payload.trim()) {
          throw new Error(`Proof ${index + 1} needs both adapterId and payload`);
        }
        return {
          adapterId: normalizeHex(
            proof.adapterId,
            `Proof ${index + 1} adapterId`,
            32,
          ),
          payload: normalizeHex(proof.payload, `Proof ${index + 1} payload`),
        };
      });

    if (parsedProofs.length === 0) {
      throw new Error('At least one proof is required');
    }

    const validatedProofs = parsedProofs.map((proof, index) => {
      const normalizedAdapter = proof.adapterId.toLowerCase();

      if (knownWorldAdapterIds.has(normalizedAdapter)) {
        validateWorldIdProofPayload(proof.payload);
      } else if (knownSelfAdapterIds.has(normalizedAdapter)) {
        validateSelfAttestationProofPayload(proof.payload);
      }

      return proof;
    });

    return {
      proofs: validatedProofs,
      nullifier: normalizeHex(nullifier, 'Nullifier', 32),
      epoch: parseUint(epoch, 'Epoch'),
    };
  };

  const connectWallet = async () => {
    setBusyAction('connect');
    setTxHash('');
    try {
      if (!window.ethereum) {
        throw new Error(
          'No injected wallet found. Open this app in a wallet-enabled browser.',
        );
      }
      const walletClient = createWalletClient({
        chain,
        transport: custom(window.ethereum),
      });
      const addresses = await walletClient.requestAddresses();
      const connected = addresses[0];
      if (!connected) {
        throw new Error('Wallet did not return an account');
      }
      setWalletAddress(connected);
      if (!userAddress.trim()) {
        setUserAddress(connected);
      }
      setSuccess(`Wallet connected: ${connected}`);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Failed to connect wallet');
    } finally {
      setBusyAction(null);
    }
  };

  const switchWalletNetwork = async () => {
    setBusyAction('switch');
    setTxHash('');

    try {
      if (!window.ethereum) {
        throw new Error('No injected wallet found. Connect a wallet first.');
      }

      const activeChainId = parseChainId(chainId);
      const chainIdHex = `0x${activeChainId.toString(16)}` as Hex;

      try {
        await window.ethereum.request({
          method: 'wallet_switchEthereumChain',
          params: [{chainId: chainIdHex}],
        });
      } catch (switchError) {
        const errorWithCode = switchError as {code?: number; message?: string};
        const shouldAddChain =
          errorWithCode.code === 4902 ||
          (errorWithCode.message ?? '').toLowerCase().includes('unrecognized chain');

        if (!shouldAddChain) {
          throw switchError;
        }

        const addChainParams: {
          chainId: Hex;
          chainName: string;
          nativeCurrency: {name: string; symbol: string; decimals: number};
          rpcUrls: string[];
          blockExplorerUrls?: string[];
        } = {
          chainId: chainIdHex,
          chainName: getChainName(activeChainId),
          nativeCurrency: {name: 'Ether', symbol: 'ETH', decimals: 18},
          rpcUrls: [rpcUrl],
        };

        if (explorerBaseUrl) {
          addChainParams.blockExplorerUrls = [explorerBaseUrl];
        }

        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [addChainParams],
        });
      }

      setSuccess(`Wallet switched to ${getChainName(activeChainId)}.`);
    } catch (error) {
      setError(
        error instanceof Error
          ? error.message
          : 'Failed to switch wallet network',
      );
    } finally {
      setBusyAction(null);
    }
  };

  const checkSatisfies = async () => {
    setBusyAction('read');
    setTxHash('');
    try {
      const bundle = buildBundle();
      const result = await publicClient.readContract({
        address: normalizeAddress(policyEngineAddress, 'PolicyEngine address'),
        abi: policyEngineAbi,
        functionName: 'satisfies',
        args: [
          parseUint(policyId, 'Policy ID'),
          normalizeAddress(userAddress || walletAddress, 'User address'),
          bundle,
        ],
      });

      if (result) {
        setSuccess(
          'satisfies() returned true. Policy conditions are met for this bundle.',
        );
      } else {
        setError('satisfies() returned false. Policy conditions are not met.');
      }
    } catch (error) {
      setError(error instanceof Error ? error.message : 'satisfies() failed');
    } finally {
      setBusyAction(null);
    }
  };

  const callBeforeSwap = async () => {
    setBusyAction('write');
    setTxHash('');
    try {
      if (!window.ethereum) {
        throw new Error('No injected wallet found. Connect a wallet first.');
      }

      const walletClient = createWalletClient({
        chain,
        transport: custom(window.ethereum),
      });
      const addresses = await walletClient.requestAddresses();
      const account = addresses[0];
      if (!account) {
        throw new Error('Wallet did not return an account');
      }

      setWalletAddress(account);

      const bundle = buildBundle();
      const sender = normalizeAddress(userAddress || account, 'Sender address');

      const hash = await walletClient.writeContract({
        account,
        chain,
        address: normalizeAddress(hookAddress, 'Hook address'),
        abi: satisfyHookAbi,
        functionName: 'beforeSwap',
        args: [normalizeHex(poolId, 'Pool ID', 32), sender, bundle],
      });

      setTxHash(hash);
      const receipt = await publicClient.waitForTransactionReceipt({hash});

      if (receipt.status === 'success') {
        setSuccess(`beforeSwap succeeded. Tx: ${hash}`);
      } else {
        setError(`beforeSwap reverted. Tx: ${hash}`);
      }
    } catch (error) {
      setError(error instanceof Error ? error.message : 'beforeSwap failed');
    } finally {
      setBusyAction(null);
    }
  };

  const updateProof = (index: number, field: keyof ProofDraft, value: string) => {
    setProofs((current) =>
      current.map((proof, i) => (i === index ? {...proof, [field]: value} : proof)),
    );
  };

  return (
    <div className="min-h-screen bg-[var(--color-dark)] text-white overflow-hidden selection:bg-[var(--color-neon)] selection:text-black">
      <div className="absolute inset-0 z-0 grid-bg opacity-50 pointer-events-none" />

      <nav className="relative z-10 border-b border-white/10 bg-black/50 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Shield className="w-6 h-6 text-[var(--color-neon)]" />
            <span className="font-display font-bold text-xl tracking-tight">Satisfy</span>
          </div>
          <button
            onClick={connectWallet}
            disabled={busyAction === 'connect'}
            className="px-4 py-2 bg-white/5 hover:bg-white/10 border border-white/10 rounded-md font-mono text-sm transition-all flex items-center gap-2 disabled:opacity-60"
          >
            {busyAction === 'connect' ? (
              <LoaderCircle className="w-4 h-4 animate-spin" />
            ) : (
              <Wallet className="w-4 h-4" />
            )}
            {walletAddress
              ? `${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}`
              : 'Connect'}
          </button>
        </div>
      </nav>

      <main className="relative z-10">
        <section className="pt-24 pb-14 px-6">
          <div className="max-w-7xl mx-auto">
            <motion.div
              initial={{opacity: 0, y: 16}}
              animate={{opacity: 1, y: 0}}
              transition={{duration: 0.6}}
            >
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[var(--color-neon)]/10 border border-[var(--color-neon)]/20 text-[var(--color-neon)] font-mono text-xs mb-8">
                <span className="w-2 h-2 rounded-full bg-[var(--color-neon)] animate-pulse" />
                Unichain-ready credential-aware liquidity hooks
              </div>
              <h1 className="font-display text-5xl md:text-7xl font-bold leading-[0.95] tracking-tighter mb-6 max-w-4xl">
                Policy-gated markets with live Unichain integration.
              </h1>
              <p className="text-xl text-gray-400 max-w-3xl mb-8">
                Frontend is wired to <code>SatisfyPolicyEngine.satisfies</code> and{' '}
                <code>SatisfyHook.beforeSwap</code>, with built-in Unichain network presets and
                wallet network switching.
              </p>
              <div className="flex flex-wrap gap-3">
                <a
                  href="#console"
                  className="px-6 py-3 bg-[var(--color-neon)] text-black font-bold rounded-none hover:bg-[#00cc76] transition-colors inline-flex items-center gap-2"
                >
                  Open Contract Console
                  <ArrowRight className="w-4 h-4" />
                </a>
                <a
                  href="#architecture"
                  className="px-6 py-3 border border-white/20 hover:border-white/40 font-mono text-sm transition-colors inline-flex items-center gap-2"
                >
                  <Terminal className="w-4 h-4" />
                  Integration Flow
                </a>
              </div>
            </motion.div>
          </div>
        </section>

        <section id="console" className="py-16 px-6 border-t border-white/10 bg-black/30">
          <div className="max-w-7xl mx-auto">
            <div className="mb-8">
              <h2 className="font-display text-4xl font-bold mb-3">Live Contract Console</h2>
              <p className="text-gray-400">
                Select Unichain network preset, connect wallet, test proofs with
                <code> satisfies()</code>, then execute <code>beforeSwap</code>.
              </p>
            </div>

            <div className="grid xl:grid-cols-3 gap-6">
              <div className="xl:col-span-2 border border-white/10 bg-white/[0.02] p-6 space-y-6">
                <div className="grid md:grid-cols-[1fr_auto] gap-4">
                  <label className="text-sm font-mono text-gray-400">
                    Network mode
                    <select
                      value={networkMode}
                      onChange={(event) => applyNetworkMode(event.target.value as NetworkMode)}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                    >
                      {networkModeOptions.map((option) => (
                        <option key={option.value} value={option.value}>
                          {option.label}
                        </option>
                      ))}
                    </select>
                  </label>

                  <button
                    onClick={switchWalletNetwork}
                    disabled={busyAction !== null}
                    className="self-end px-4 py-2 bg-white/5 hover:bg-white/10 border border-white/15 font-mono text-sm inline-flex items-center gap-2 disabled:opacity-60"
                  >
                    {busyAction === 'switch' ? (
                      <LoaderCircle className="w-4 h-4 animate-spin" />
                    ) : (
                      <Network className="w-4 h-4" />
                    )}
                    Switch Wallet Network
                  </button>
                </div>

                <div className="grid md:grid-cols-2 gap-4">
                  <label className="text-sm font-mono text-gray-400">
                    RPC URL
                    <input
                      value={rpcUrl}
                      onChange={(event) => setRpcUrl(event.target.value)}
                      disabled={networkMode !== 'custom'}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 disabled:opacity-60 focus:border-[var(--color-neon)] outline-none"
                    />
                  </label>
                  <label className="text-sm font-mono text-gray-400">
                    Chain ID
                    <input
                      value={chainId}
                      onChange={(event) => setChainId(event.target.value)}
                      disabled={networkMode !== 'custom'}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 disabled:opacity-60 focus:border-[var(--color-neon)] outline-none"
                    />
                  </label>
                  <label className="text-sm font-mono text-gray-400">
                    PolicyEngine address
                    <input
                      value={policyEngineAddress}
                      onChange={(event) => setPolicyEngineAddress(event.target.value)}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                    />
                  </label>
                  <label className="text-sm font-mono text-gray-400">
                    Hook address
                    <input
                      value={hookAddress}
                      onChange={(event) => setHookAddress(event.target.value)}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                    />
                  </label>
                  <label className="text-sm font-mono text-gray-400">
                    Policy ID
                    <input
                      value={policyId}
                      onChange={(event) => setPolicyId(event.target.value)}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                    />
                  </label>
                  <label className="text-sm font-mono text-gray-400">
                    Pool ID (bytes32)
                    <input
                      value={poolId}
                      onChange={(event) => setPoolId(event.target.value)}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                    />
                  </label>
                  <label className="text-sm font-mono text-gray-400">
                    Sender/User address
                    <input
                      value={userAddress}
                      onChange={(event) => setUserAddress(event.target.value)}
                      placeholder={walletAddress || '0x...'}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                    />
                  </label>
                  <label className="text-sm font-mono text-gray-400">
                    Epoch
                    <input
                      value={epoch}
                      onChange={(event) => setEpoch(event.target.value)}
                      className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                    />
                  </label>
                </div>

                <div>
                  <div className="flex items-center justify-between mb-3">
                    <h3 className="font-display text-xl">Proof Bundle</h3>
                    <button
                      onClick={() =>
                        setProofs((current) => [
                          ...current,
                          {adapterId: '', payload: '0x'},
                        ])
                      }
                      className="px-3 py-2 bg-white/5 hover:bg-white/10 border border-white/15 text-sm font-mono flex items-center gap-2"
                    >
                      <Plus className="w-4 h-4" />
                      Add Proof
                    </button>
                  </div>

                  <div className="space-y-3">
                    {proofs.map((proof, index) => (
                      <div key={index} className="p-4 border border-white/10 bg-black/20">
                        <div className="flex items-center justify-between mb-3">
                          <span className="font-mono text-xs text-gray-400">
                            Proof #{index + 1}
                          </span>
                          {proofs.length > 1 && (
                            <button
                              onClick={() =>
                                setProofs((current) =>
                                  current.filter((_, i) => i !== index),
                                )
                              }
                              className="text-gray-400 hover:text-red-400"
                            >
                              <Trash2 className="w-4 h-4" />
                            </button>
                          )}
                        </div>
                        <div className="grid md:grid-cols-2 gap-3">
                          <label className="text-xs font-mono text-gray-400">
                            adapterId (bytes32)
                            <input
                              value={proof.adapterId}
                              onChange={(event) =>
                                updateProof(index, 'adapterId', event.target.value)
                              }
                              className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                            />
                          </label>
                          <label className="text-xs font-mono text-gray-400">
                            payload (bytes)
                            <input
                              value={proof.payload}
                              onChange={(event) =>
                                updateProof(index, 'payload', event.target.value)
                              }
                              className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                            />
                          </label>
                        </div>
                      </div>
                    ))}
                  </div>

                  <div className="grid md:grid-cols-[1fr_auto] gap-3 mt-4">
                    <label className="text-sm font-mono text-gray-400">
                      Nullifier (bytes32)
                      <input
                        value={nullifier}
                        onChange={(event) => setNullifier(event.target.value as Hex)}
                        className="mt-2 w-full px-3 py-2 bg-black/40 border border-white/15 focus:border-[var(--color-neon)] outline-none"
                      />
                    </label>
                    <button
                      onClick={() => setNullifier(randomHex32())}
                      className="self-end px-4 py-2 bg-white/5 hover:bg-white/10 border border-white/15 font-mono text-sm"
                    >
                      Randomize
                    </button>
                  </div>
                </div>

                <div className="flex flex-wrap gap-3">
                  <button
                    onClick={checkSatisfies}
                    disabled={busyAction !== null}
                    className="px-5 py-3 bg-white text-black font-bold hover:bg-gray-200 transition-colors disabled:opacity-60 inline-flex items-center gap-2"
                  >
                    {busyAction === 'read' ? (
                      <LoaderCircle className="w-4 h-4 animate-spin" />
                    ) : (
                      <CheckCircle2 className="w-4 h-4" />
                    )}
                    Check satisfies()
                  </button>
                  <button
                    onClick={callBeforeSwap}
                    disabled={busyAction !== null}
                    className="px-5 py-3 bg-[var(--color-neon)] text-black font-bold hover:bg-[#00cc76] transition-colors disabled:opacity-60 inline-flex items-center gap-2"
                  >
                    {busyAction === 'write' ? (
                      <LoaderCircle className="w-4 h-4 animate-spin" />
                    ) : (
                      <Send className="w-4 h-4" />
                    )}
                    Submit beforeSwap
                  </button>
                </div>
              </div>

              <aside className="space-y-4">
                <div className="border border-white/10 bg-black/30 p-5">
                  <h3 className="font-display text-xl mb-3">Execution Status</h3>
                  <p
                    className={`text-sm leading-relaxed ${
                      statusTone === 'success'
                        ? 'text-emerald-400'
                        : statusTone === 'error'
                          ? 'text-red-400'
                          : 'text-gray-300'
                    }`}
                  >
                    {statusMessage}
                  </p>
                  {txHash && (
                    <p className="mt-3 text-xs font-mono break-all text-gray-400">
                      txHash: {txHash}
                    </p>
                  )}
                  {txExplorerUrl && (
                    <a
                      href={txExplorerUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="mt-2 inline-block text-xs font-mono text-[var(--color-neon)] hover:underline"
                    >
                      Open in explorer
                    </a>
                  )}
                </div>

                <div className="border border-white/10 bg-black/30 p-5 space-y-3">
                  <h3 className="font-display text-xl">Expected Data Shape</h3>
                  <CodeBlock
                    code={`bundle = {
  proofs: [
    { adapterId: bytes32, payload: bytes },
    ...
  ],
  nullifier: bytes32,
  epoch: uint64
}`}
                  />
                </div>

                <div className="border border-white/10 bg-black/30 p-5 text-sm text-gray-400">
                  <p className="mb-2">
                    <span className="text-[var(--color-neon)] font-mono">Tip:</span>{' '}
                    Use deployment output from <code>./script/deploy_unichain.sh</code>{' '}
                    and copy values into <code>frontend/.env.local</code>.
                  </p>
                  <p>
                    Connected account must be an authorized hook caller for{' '}
                    <code>beforeSwap</code> to succeed.
                  </p>
                </div>
              </aside>
            </div>
          </div>
        </section>

        <section id="architecture" className="py-20 px-6 border-t border-white/10 bg-black/20">
          <div className="max-w-7xl mx-auto grid lg:grid-cols-2 gap-10 items-center">
            <div>
              <h2 className="font-display text-4xl font-bold mb-5">Integration Flow</h2>
              <div className="space-y-4 text-gray-400">
                <p>1. Select Unichain network preset and switch wallet chain.</p>
                <p>
                  2. Frontend calls <code>satisfies(policyId, user, bundle)</code> for a dry policy check.
                </p>
                <p>
                  3. Frontend sends <code>beforeSwap(poolId, sender, bundle)</code> through wallet signer.
                </p>
                <p>
                  4. Hook forwards to policy engine and consumes nullifier on success.
                </p>
              </div>
            </div>
            <CodeBlock
              code={`SatisfyPolicyEngine.satisfies(policyId, user, bundle)
SatisfyHook.beforeSwap(poolId, sender, bundle)

bundle.proofs[] = {
  adapterId: bytes32,
  payload: bytes
}`}
            />
          </div>
        </section>

        <section className="py-24 px-6 text-center border-t border-white/10">
          <Fingerprint className="w-16 h-16 text-[var(--color-neon)] mx-auto mb-8 opacity-60" />
          <h2 className="font-display text-4xl font-bold mb-4">
            Minimum disclosure, maximum coordination.
          </h2>
          <p className="text-xl text-gray-400 max-w-3xl mx-auto">
            Credential-aware market controls without address-based surveillance.
          </p>
        </section>
      </main>

      <footer className="border-t border-white/10 bg-black py-10 px-6">
        <div className="max-w-7xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4 text-sm text-gray-500">
          <div className="flex items-center gap-2 text-white">
            <Shield className="w-5 h-5 text-[var(--color-neon)]" />
            <span className="font-display font-bold tracking-tight">Satisfy</span>
          </div>
          <div>Unichain-integrated frontend for policy-gated liquidity.</div>
        </div>
      </footer>
    </div>
  );
}
