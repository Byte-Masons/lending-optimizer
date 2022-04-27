async function main() {
  const vaultAddress = '0x71b2e2eDfE6E881c126c4fE2cCBa553B42ACFEB9';
  const strategyAddress = '0x235A76b2747728Ec5CBBc36642dc27308C9189be';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
  const vault = Vault.attach(vaultAddress);

  await vault.initialize(strategyAddress);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
