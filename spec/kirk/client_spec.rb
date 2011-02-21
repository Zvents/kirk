require 'spec_helper'
require 'kirk/client'

import org.eclipse.jetty.util.thread.QueuedThreadPool

describe 'Kirk::Client' do

  describe "requests" do
    before do
      start echo_app_path('config.ru')
    end

    it "allows to pass block for request" do
      handler = Class.new do
        def initialize(buffer)
          @buffer = buffer
        end

        def on_response_complete(response)
          @buffer << response
        end
      end

      @buffer = []
      group = Kirk::Client.group(:host => "localhost:9090") do |g|
        body = "foobar"

        g.request do |r|
          r.method  :post
          r.url     "/foo"
          r.handler handler.new(@buffer)
          r.headers "Accept" => "text/plain"
          r.body    body
        end
      end

      response = parse_response(group.responses.first)
      response["PATH_INFO"].should == "/foo"
      response["HTTP_ACCEPT"].should == "text/plain"
      response["REQUEST_METHOD"].should == "POST"
      response["rack.input"].should == "foobar"
      @buffer.should == group.responses
    end

    it "allows to use simplified syntax" do
      group = Kirk::Client.group(:host => "localhost:9090") do |g|
        g.get    '/'
        g.put    '/'
        g.post   '/'
        g.delete '/'
      end

      responses = parse_responses(group.responses)
      responses.map {|r| r["REQUEST_METHOD"] }.sort.should == ["DELETE", "GET", "POST", "PUT"]
    end

    it "performs simple GET" do
      group = Kirk::Client.group do |s|
        s.request :GET, "http://localhost:9090/"
      end

      group.should have(1).responses
      response = parse_response(group.responses.first)
      response["PATH_INFO"].should == "/"
      response["REQUEST_METHOD"].should == "GET"
    end

    it "performs more than one GET" do
      group = Kirk::Client.group do |s|
        s.request :GET, "http://localhost:9090/foo"
        s.request :GET, "http://localhost:9090/bar"
      end

      group.should have(2).responses
      parse_responses(group.responses).map { |r| r["PATH_INFO"] }.sort.should == %w(/bar /foo)
    end

    it "performs POST request" do
      body = "zomg"
      group = Kirk::Client.group do |g|
        g.request :POST, "http://localhost:9090/", nil, body, {'Accept' => 'text/html'}
      end

      response = parse_response(group.responses.first)
      response["HTTP_ACCEPT"].should    == "text/html"
      response["REQUEST_METHOD"].should == "POST"
      response["rack.input"].should     == "zomg"
    end

    it "allows to pass body as IO" do
      body = StringIO.new "zomg"
      group = Kirk::Client.group do |g|
        g.request :POST, "http://localhost:9090/", nil, body
      end

      response = parse_response(group.responses.first)
      response["rack.input"].should == "zomg"
    end
  end

  it "fetches all the headers" do
    headers = { 'Content-Type' => 'text/plain', 'X-FooBar' => "zomg" }
    start(lambda { |env| [ 200, headers, [ "Hello" ] ] })

    headers.to_a.sort { |a, b| a.first <=> b.first }.should ==
      [['Content-Type', 'text/plain'], ['X-FooBar', 'zomg']]
  end

  it "allows to stream body" do
    handler = Class.new do
      def initialize(buffer)
        @buffer = buffer
      end

      def on_response_content(content)
        @buffer << content
      end
    end

    start(lambda do |env|
      [ 200, { 'Content-Type' => 'text/plain' }, [ "a" * 10000 ] ]
    end)

    @buffer = []

    group = Kirk::Client.group do |s|
      s.request :GET, "http://localhost:9090/", handler.new(@buffer)
    end

    sleep(0.05)
    group.should have(1).responses
    @buffer.length.should be > 1
  end

  context "callbacks" do
    it "handles on_response_complete callback" do
      handler = Class.new do
        def initialize(buffer)
          @buffer = buffer
        end

        def on_response_complete(response)
          @buffer << response
        end
      end

      start_default_app

      @buffer = []
      group = Kirk::Client.group do |s|
        s.request :GET, "http://localhost:9090/", handler.new(@buffer)
      end

      sleep(0.05)
      @buffer.first.should == group.responses.first
    end

    it "handles on_response_header callback" do
      handler = Class.new do
        def initialize(buffer)
          @buffer = buffer
        end

        def on_response_header(headers)
          @buffer << headers
        end
      end

      start_default_app

      @buffer = []
      group = Kirk::Client.group do |s|
        s.request :GET, "http://localhost:9090/", handler.new(@buffer)
      end

      sleep(0.05)
      @buffer.first.should == {'Content-Type' => 'text/plain'}
    end

    it "calls complete callback after finishing all the requests" do
      start_default_app

      @completed = false
      group = Kirk::Client.group(:host => "localhost:9090") do |g|
        g.get "/"
        g.complete do
          @completed = true
        end
      end

      group.should have(1).responses
      @completed.should be_true
    end
  end

  it "allows to set thread_pool" do
    thread_pool = QueuedThreadPool.new
    client = Kirk::Client.new(:thread_pool => thread_pool)
    client.client.get_thread_pool.should == thread_pool
    client.stop
  end

  it "allows to run group on instance" do
    start_default_app

    client = Kirk::Client.new
    result = client.group do |g|
      g.request :GET, "http://localhost:9090/"
    end

    result.responses.first.body.should == "Hello"
  end

  it "allows to set host for group" do
    start_default_app

    group = Kirk::Client.group(:host => "localhost:9090") do |g|
      g.request :GET, "/"
    end

    group.responses.first.body.should == "Hello"
  end

  it "allows to avoid blocking" do
    start(lambda { |env| sleep(0.1); [ 200, {}, 'Hello' ] })

    group = Kirk::Client.group(:host => "localhost:9090", :block => false) do |g|
      g.get "/"
    end

    group.should have(0).responses

    group.join
    group.should have(1).responses
  end

  it "passes self to group" do
    client = Kirk::Client.new
    group = client.group {}
    group.client.should == client
  end

  def start_default_app
    start(lambda { |env| [ 200, { 'Content-Type' => 'text/plain' }, [ "Hello" ] ] })
  end

  def parse_response(response)
    Marshal.load(response.body)
  end

  def parse_responses(responses)
    responses.map { |r| parse_response(r) }
  end
end
