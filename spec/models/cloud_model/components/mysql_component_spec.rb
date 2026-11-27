# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::MysqlComponent do
  it 'should carry the series in its name and resolve its worker' do
    component = CloudModel::Components::BaseComponent.from_sym :"mysql@8.4"
    expect(component).to be_a described_class
    expect(component.human_name).to eq 'MySQL 8.4'
    expect(component.worker(double(arch: 'amd64'), double)).to be_a CloudModel::Workers::Components::MysqlComponentWorker
  end
end
