.PHONY: build test e2e e2e-external fmt clean

build:
	forge build --offline

test:
	forge test --offline

e2e:
	./script/anvil_e2e.sh

e2e-external:
	RPC_URL=http://127.0.0.1:8545 START_ANVIL=0 ./script/anvil_e2e.sh

fmt:
	forge fmt

clean:
	rm -rf out cache
