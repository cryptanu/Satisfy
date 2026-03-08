.PHONY: build test e2e e2e-external deploy-unichain-sepolia deploy-unichain-mainnet relay-self-mock sync-frontend-artifact ci-real-data frontend-install frontend-dev frontend-build fmt clean

build:
	forge build --offline

test:
	forge test --offline

e2e:
	./script/anvil_e2e.sh

e2e-external:
	RPC_URL=http://127.0.0.1:8545 START_ANVIL=0 ./script/anvil_e2e.sh

deploy-unichain-sepolia:
	UNICHAIN_NETWORK=sepolia ./script/deploy_unichain.sh

deploy-unichain-mainnet:
	UNICHAIN_NETWORK=mainnet ./script/deploy_unichain.sh

relay-self-mock:
	./script/relay_self_attestation_mock.sh

sync-frontend-artifact:
	./script/sync_frontend_artifact.sh deployments/unichain-sepolia.json

ci-real-data:
	./script/ci_real_data_replay.sh

frontend-install:
	npm --prefix frontend install

frontend-dev:
	npm --prefix frontend run dev

frontend-build:
	npm --prefix frontend run build

fmt:
	forge fmt

clean:
	rm -rf out cache frontend/dist
