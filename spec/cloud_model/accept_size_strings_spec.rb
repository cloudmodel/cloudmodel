# encoding: UTF-8

require 'spec_helper'

describe CloudModel::AcceptSizeStrings do
  class TestAcceptSizeStringsModel
    include Mongoid::Document
    include CloudModel::AcceptSizeStrings
    
    field :size, type: Integer, default: 0
    accept_size_strings_for :size
  end
  
  subject { TestAcceptSizeStringsModel.new }
  
  it "should accept pure bytes as number" do
    subject.size = 512
    expect(subject.size).to eq 512
  end
  
  it "should accept pure bytes as string" do
    subject.size = "512"
    expect(subject.size).to eq 512
  end
  
  it "should accept sizes in KiB" do
    subject.size = "8 KiB"
    expect(subject.size).to eq 8192
  end
 
  it "should accept sizes in K" do
    subject.size = "8K"
    expect(subject.size).to eq 8192
  end
  
  it "should accept sizes in MiB" do
    subject.size = "2 MiB"
    expect(subject.size).to eq 2097152
  end
 
  it "should accept sizes in M" do
    subject.size = "2M"
    expect(subject.size).to eq 2097152
  end
  
  it "should accept sizes in GiB" do
    subject.size = "4 GiB"
    expect(subject.size).to eq 4294967296
  end
 
  it "should accept sizes in G" do
    subject.size = "4G"
    expect(subject.size).to eq 4294967296
  end
  
  it "should accept sizes in TiB" do
    subject.size = "1 TiB"
    expect(subject.size).to eq 1099511627776
  end
 
  it "should accept sizes in T" do
    subject.size = "1T"
    expect(subject.size).to eq 1099511627776
  end
  
  context 'invalid input format' do
    it "should not change size value if format was wrong" do
      subject.size = "1 Terra Byte"
      expect(subject.size).to eq 0
    end
    
    xit "should not be valid if format was wrong" do
      subject.size = "1 Terra Byte"
      expect(subject.valid?).to be false
    end
    
    it "should add a validation error if format was wrong" do
      subject.size = "1 Terra Byte"
      expect(subject.errors.to_a).to eq ["Size has to be a number optional followed by K, M, G, T or KiB, MiB, GiB, TiB"]
    end
  end
end