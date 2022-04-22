async function main() {
  const vaultAddress = '0x8a3B04BAB70e96D8cA1Ff6072f3ceb3F59b477A8';
  const strategyAddress = '0x2b8924e7d06B54a2FeD6939990DB13d63911c12B';

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
