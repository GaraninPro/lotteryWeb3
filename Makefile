-include .env
deploy:
	forge script script/DeployRaffle.s.sol --rpc-url $(RPC2) --private-key $(KEY2) --etherscan-api-key $(SCAN) --broadcast --verify