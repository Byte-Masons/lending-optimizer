async function main() {
  const vaultAddress = '0x1D2BCA5a4F571366650966949c7c1D86C571fa24';
  const strategyAddress = '0x4947157fD7CdFcf3f2D92d4ABf9a238bccDc7946';

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
