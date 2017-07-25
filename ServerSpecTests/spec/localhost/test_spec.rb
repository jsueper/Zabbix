## ref. http://serverspec.org/resource_types.html
## gem install serverspec
## serverspec-init  # note: select OS, select local or ssh execution

require 'spec_helper'

# check if service is up
describe service('kafka') do
  it { should be_running }
end

# check volumes
describe file('/dev/xvda1') do
  it { should be_block_device }
end

# check port
describe port(2181) do
  it { should be_listening.with('tcp') }
end

# check port
describe port(8080) do
  it { should be_listening.with('tcp') }
end

describe host('google.com') do
  it { should be_resolvable }
end
