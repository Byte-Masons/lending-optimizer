async function main() {
  const vaultAddress = '0xb4bb795B165FB0fBF11598a3c6E3D011EF5d9dF8';
  const strategyAddress = '0x8858C3FEF08f66db12983893c326E3E46c94c539';

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
