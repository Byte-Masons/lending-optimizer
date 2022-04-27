async function main() {
  const vaultAddress = '0x41a5463aebB713B9DA079ED646c11b1Aaa8E9C1E';
  const strategyAddress = '0xe5D265779CEFDb537352F9Debda326573027B73A';

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
