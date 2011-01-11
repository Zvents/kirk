require 'spec_helper'
require 'openssl'

describe 'Kirk::InputStream' do

  CHUNK_SIZE    =   4 * 1_024
  GIBBERISH_LEN = 256 * 1_024
  GIBBERISH     = OpenSSL::Random.random_bytes(GIBBERISH_LEN)

  def with_input_stream
    r, w  = IO.pipe
    input = Kirk::InputStream.new(r.to_inputstream)
    yield input, w
    input.read # clear the pipes
    @thread.join if @thread
    w.close unless w.closed?
    input
  end

  def each_chunk(str, chunk_size = CHUNK_SIZE)
    pos = 0
    until pos >= str.length
      yield str[pos, chunk_size]
      pos += chunk_size
    end
    str
  end

  def stream(io, str)
    each_chunk(str) { |chunk| io << chunk }
  end

  def stream_in_bg(io, str)
    @thread = Thread.new do
      stream io, str
      io.close
    end
  end

  it "reads a short, single chunk stream" do
    with_input_stream do |input, writer|
      writer << "zomgzomg"
      writer.close
      input.read.should == "zomgzomg"
    end
  end

  it "returns nil when calling #read after reaching EOF" do
    with_input_stream do |input, writer|
      writer << "zomgzomg"
      writer.close
      input.read
      input.read.should be_nil
    end
  end

  it "reads a short, multi chunk stream" do
    with_input_stream do |input, writer|
      writer << "zomg" << "zomg"
      writer.close
      input.read.should == "zomgzomg"
    end
  end

  it "can specify the chunk size to read" do
    with_input_stream do |input, writer|
      writer << "zomgzomg"
      writer.close

      input.read(4).should == "zomg"
      input.read(4).should == "zomg"
      input.read(4).should be_nil
    end
  end

  it "raises if trying to seek to a negative value" do
    with_input_stream do |input, writer|
      writer << "zomgzomg"
      writer.close

      lambda { input.seek(-1) }.should raise_error(Errno::EINVAL)
    end
  end

  it "can rewind to the start of the chunk" do
    with_input_stream do |input, writer|
      writer << "zomgzomg"
      writer.close

      input.read.should == "zomgzomg"
      input.rewind
      input.read.should == "zomgzomg"
      input.read.should be_nil
    end
  end

  it "can seek ahead of what is currently read" do
    with_input_stream do |input, writer|
      writer << "zomgzomg"
      writer.close

      input.seek(6)
      input.read.should == "mg"
      input.rewind
      input.read.should == "zomgzomg"
    end
  end

  it "reads large streams in one call" do
    with_input_stream do |input, writer|
      stream_in_bg writer, GIBBERISH
      input.read.should == GIBBERISH
    end
  end

  it "reads large streams in multiple calls" do
    with_input_stream do |input, writer|
      stream_in_bg writer, GIBBERISH

      each_chunk GIBBERISH, 1_024 do |chunk|
        input.read(1_024).should == chunk
      end

      input.read(1_024).should be_nil
    end
  end

  it "can seek to a point that will be buffered in memory" do
    with_input_stream do |input, writer|
      stream_in_bg writer, GIBBERISH

      input.seek(1_234)
      input.read(2_048).should == GIBBERISH[1_234, 2_048]
    end
  end

  it "can seek to a point that will be buffered to a file" do
    with_input_stream do |input, writer|
      stream_in_bg writer, GIBBERISH

      input.seek(75_000)
      chunk = input.read(5_322)
      chunk.length.should == 5_322
      chunk.should == GIBBERISH[75_000, 5_322]
    end
  end

  it "can rewind after seeking to a point that will be buffered to a file" do
    with_input_stream do |input, writer|
      stream_in_bg writer, GIBBERISH

      input.seek(75_000)
      input.rewind
      input.read(4_096).should == GIBBERISH[0, 4_096]
    end
  end
end
