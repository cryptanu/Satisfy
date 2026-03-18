.PHONY: build test e2e e2e-external deploy-unichain-sepolia deploy-unichain-mainnet deploy-unichain-v2-sepolia deploy-unichain-v2-mainnet deploy-reactive-pipeline unichain-smoke unichain-smoke-v2 relay-self-mock reactive-worker reactive-executor sync-frontend-artifact ci-real-data ci-unichain-smoke build-realdata-fixture frontend-install frontend-dev frontend-build backend-install backend-dev backend-test backend-build fmt clean

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

deploy-unichain-v2-sepolia:
	UNICHAIN_NETWORK=sepolia ./script/deploy_unichain_v2.sh

deploy-unichain-v2-mainnet:
	UNICHAIN_NETWORK=mainnet ./script/deploy_unichain_v2.sh

deploy-reactive-pipeline:
	./script/deploy_reactive_pipeline.sh deployments/unichain-sepolia.json

unichain-smoke:
	./script/unichain_smoke.sh deployments/unichain-sepolia.json

unichain-smoke-v2:
	./script/unichain_smoke.sh deployments/unichain-sepolia-v2-agentkit.json

relay-self-mock:
	./script/relay_self_attestation_mock.sh

reactive-worker:
	./script/reactive_event_executor.sh deployments/unichain-sepolia.json

reactive-executor: reactive-worker

sync-frontend-artifact:
	./script/sync_frontend_artifact.sh deployments/unichain-sepolia.json

ci-real-data:
	./script/ci_real_data_replay.sh

ci-unichain-smoke:
	./script/ci_unichain_smoke.sh

build-realdata-fixture:
	./script/build_realdata_fixture.sh

frontend-install:
	npm --prefix frontend install

frontend-dev:
	npm --prefix frontend run dev

frontend-build:
	npm --prefix frontend run build

backend-install:
	npm --prefix services/agentkit-gateway install

backend-dev:
	npm --prefix services/agentkit-gateway run dev

backend-test:
	npm --prefix services/agentkit-gateway test

backend-build:
	npm --prefix services/agentkit-gateway run build

fmt:
	forge fmt

clean:
	rm -rf out cache frontend/dist services/agentkit-gateway/dist
