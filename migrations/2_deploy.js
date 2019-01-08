const MemberRoles = artifacts.require('MemberRoles');
const GovBlocksMaster = artifacts.require('GovBlocksMaster');
const Master = artifacts.require('Master');
const GBTStandardToken = artifacts.require('GBTStandardToken');
const Governance = artifacts.require('Governance');
const ProposalCategory = artifacts.require('ProposalCategory');
const EventCaller = artifacts.require('EventCaller');

module.exports = function(deployer) {
  deployer.then(async () => {
    ec = await deployer.deploy(EventCaller);
    await deployer.deploy(GBTStandardToken);
    await deployer.deploy(GovBlocksMaster,ec.address);
    await deployer.deploy(Governance);
    await deployer.deploy(ProposalCategory);
    await deployer.deploy(MemberRoles);
    await deployer.deploy(Master);
  });
};