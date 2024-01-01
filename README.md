## Tornado

# phase1

```
mkdir -p build
snarkjs powersoftau new bn128 15 build/pot15_0000.ptau -v
openssl rand -hex 10 | snarkjs powersoftau contribute build/pot15_0000.ptau build/pot15_0001.ptau --name="First contribution" -v

snarkjs powersoftau prepare phase2 build/pot15_0001.ptau build/pot15_final.ptau -v
```

# phase2

```
circom circuits/withdraw.circom --r1cs --wasm --sym -o build
snarkjs groth16 setup build/withdraw.r1cs build/pot15_final.ptau build/withdraw_0000.zkey
openssl rand -hex 10 | snarkjs zkey contribute build/withdraw_0000.zkey build/withdraw_0001.zkey --name="1st Contributor Name" -v
snarkjs zkey export verificationkey build/withdraw_0001.zkey build/verification_key.json

snarkjs zkey export solidityverifier build/withdraw_0001.zkey src/Verifier.sol
forge fmt
sed -i -e 's/pragma solidity \^0.8.11/pragma solidity 0.8.23/g' ./src/Verifier.sol
```

# test

```
forge test -vvv
```

ref

tornado: https://github.com/tornadocash/tornado-core

https://github.com/minaminao/tornado-cats/tree/main
