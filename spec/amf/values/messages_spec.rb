require File.dirname(__FILE__) + '/../../spec_helper.rb'

describe RocketAMF::Values::AbstractMessage do
  before :each do
    @message = RocketAMF::Values::AbstractMessage.new
  end

  it "should generate conforming uuids" do
    @message.send(:rand_uuid).should =~ /[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}/i
  end
end

describe RocketAMF::Values::ErrorMessage do
  before :each do
    @e = Exception.new('Error message')
    @e.set_backtrace(['Backtrace 1', 'Backtrace 2'])
    @message = RocketAMF::Values::ErrorMessage.new(nil, @e)
  end

  it "should serialize as a hash in AMF0" do
    response = RocketAMF::Envelope.new
    response.messages << RocketAMF::Message.new('1/onStatus', '', @message)
    response.serialize.should == request_fixture('amf0-error-response.bin')
  end

  it "should extract exception properties correctly" do
    @message.faultCode.should == 'Exception'
    @message.faultString.should == 'Error message'
    @message.faultDetail.should == "Backtrace 1\nBacktrace 2"
  end
end