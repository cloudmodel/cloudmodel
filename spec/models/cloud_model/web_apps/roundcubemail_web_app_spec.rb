require 'spec_helper'

describe CloudModel::WebApps::RoundcubemailWebApp do
  it { expect(subject).to be_a CloudModel::WebApp }

  pending 'RoundCube Mail does not work right now and needs some more work'
end