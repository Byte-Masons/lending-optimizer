async function main() {
  const vaultAddress = '0x297c228B119f0d185a5D68a881D6E3637C008b5b';
  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
  const vault = Vault.attach(vaultAddress);
  await vault.depositAll();
  console.log('deposit complete');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
