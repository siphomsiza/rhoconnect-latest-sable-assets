# Taken from http://github.com/voloko/redis-model
require File.join(File.dirname(__FILE__),'spec_helper')

describe Rhoconnect::StoreOrm do

  context "DSL" do
    class TestDSL < Rhoconnect::StoreOrm
      field :foo
      list  :bar
      set   :sloppy
    end

    before(:each) do
      @x = TestDSL.with_key(1)
    end

    it "should define rw accessors for field" do
      @x.should respond_to(:foo)
      @x.should respond_to(:foo=)
    end

    it "should define r accessor for list" do
      @x.should respond_to(:bar)
    end

    it "should define r accessor for set" do
      @x.should respond_to(:sloppy)
    end

    it "should raise error on invalid type" do
      lambda do
        class TestInvalidType < Rhoconnect::StoreOrm
          field :invalid, :invalid_type
        end
      end.should raise_error(ArgumentError, 'Unknown type invalid_type for field invalid')
    end
  end

  context "field type cast" do
    class TestType < Rhoconnect::StoreOrm
      field :foo_string, :string
      field :foo_json,   :json
      field :foo_date,   :datetime
      field :foo_int,    :int
      field :foo_float,  :float

      list  :list_date,  :datetime
      set   :set_date,   :datetime
    end

    class TestValidateType < Rhoconnect::StoreOrm
      field :v_field, :string
      validates_presence_of :v_field
    end

    class TestLoadType < Rhoconnect::StoreOrm
      field :something, :string
      attr_accessor :foo
    end

    before(:each) do
      Store.create
      Store.flush_all
      @xRedisMock = RSpec::Mocks::Mock.new
      @yRedisMock = RSpec::Mocks::Mock.new
      @xRedisDbMock = RSpec::Mocks::Mock.new
      @yRedisDbMock = RSpec::Mocks::Mock.new
      @x = TestType.with_key(1)
      @y = TestType.with_key(1)
      @x.stub(:store).and_return(@xRedisMock)
      @y.stub(:store).and_return(@yRedisMock)
      @xRedisMock.stub(:db).and_return(@xRedisDbMock)
      @yRedisMock.stub(:db).and_return(@yRedisDbMock)
    end

    it "should create with string id" do
      @x = TestType.create(:id => 'test')
      @x.id.should == 'test'
    end

    it "should create with auto-increment id" do
      @x = TestType.create
      @x1 = TestType.create
      @x1.id.should == @x.id + 1
    end

    it "should raise ArgumentError on create with duplicate id" do
      @x = TestType.create(:id => 'test1')
      lambda { TestType.create(:id => 'test1') }.should
        raise_error(ArgumentError, "Record already exists for 'test1'")
    end

    it "should validate_presence_of v_field" do
      lambda { TestValidateType.create(:id => 'test2') }.should
        raise_error(ArgumentError, "Missing required field 'v_field'")
    end

    it "should load with attributes set" do
      TestLoadType.create(:id => 'test2')
      @x = TestLoadType.load('test2',{:foo => 'bar'})
      @x.foo.should == 'bar'
    end

    it "should save string as is" do
      @xRedisMock.should_receive(:put_value).with('test_type:1:foo_string', 'xxx')
      @yRedisMock.should_receive(:get_value).with('test_type:1:foo_string').and_return('xxx')
      @x.foo_string = 'xxx'
      @y.foo_string.should be_instance_of(String)
    end

    it "should marshal integer fields" do
      @xRedisMock.should_receive(:put_value).with('test_type:1:foo_int', '12')
      @yRedisMock.should_receive(:get_value).with('test_type:1:foo_int').and_return('12')
      @x.foo_int = 12
      @y.foo_int.should be_kind_of(Integer)
      @y.foo_int.should == 12
    end

    it "should marshal float fields" do
      @xRedisMock.should_receive(:put_value).with('test_type:1:foo_float', '12.1')
      @yRedisMock.should_receive(:get_value).with('test_type:1:foo_float').and_return('12.1')
      @x.foo_float = 12.1
      @y.foo_float.should be_kind_of(Float)
      @y.foo_float.should == 12.1
    end

    it "should marshal datetime fields" do
      time = DateTime.now
      str  = time.strftime('%FT%T%z')
      @xRedisMock.should_receive(:put_value).with('test_type:1:foo_date', str)
      @yRedisMock.should_receive(:get_value).with('test_type:1:foo_date').and_return(str)
      @x.foo_date = time
      @y.foo_date.should be_kind_of(DateTime)
      @y.foo_date.should.to_s == time.to_s
    end

    it "should marshal json structs" do
      data = {'foo' => 'bar', 'x' => 2}
      str  = JSON.dump(data)
      @xRedisMock.should_receive(:put_value).with('test_type:1:foo_json', str)
      @yRedisMock.should_receive(:get_value).with('test_type:1:foo_json').and_return(str)
      @x.foo_json = data
      @y.foo_json.should be_kind_of(Hash)
      @y.foo_json.should.inspect == data.inspect
    end

    it "should return nil for empty fields" do
      @xRedisMock.should_receive(:get_value).with('test_type:1:foo_date').and_return(nil)
      @x.foo_date.should be_nil
    end

    it "should marshal list values" do
      data = DateTime.now
      str  = data.strftime('%FT%T%z')

      @xRedisDbMock.should_receive('rpush').with('test_type:1:list_date', str)
      @xRedisDbMock.should_receive('lset').with('test_type:1:list_date', 1, str)
      @xRedisDbMock.should_receive('exists').with('test_type:1:list_date', str)
      @xRedisDbMock.should_receive('lrem').with('test_type:1:list_date', 0, str)
      @xRedisDbMock.should_receive('lpush').with('test_type:1:list_date', str)
      @xRedisDbMock.should_receive('lrange').with('test_type:1:list_date', 0, 1).and_return([str])
      @xRedisDbMock.should_receive('rpop').with('test_type:1:list_date').and_return(str)
      @xRedisDbMock.should_receive('lpop').with('test_type:1:list_date').and_return(str)
      @xRedisDbMock.should_receive('lindex').with('test_type:1:list_date', 0).and_return(str)
      @x.list_date << data
      @x.list_date[1] = data
      @x.list_date.include?(data)
      @x.list_date.remove(0, data)
      @x.list_date.push_head(data)
      @x.list_date[0].should be_kind_of(DateTime)
      @x.list_date[0, 1][0].should be_kind_of(DateTime)
      @x.list_date.pop_tail.should be_kind_of(DateTime)
      @x.list_date.pop_head.should be_kind_of(DateTime)
    end

    it "should marshal set values" do
      data = DateTime.now
      str  = data.strftime('%FT%T%z')

      @xRedisDbMock.should_receive('sadd').with('test_type:1:set_date', str)
      @xRedisDbMock.should_receive('srem').with('test_type:1:set_date', str)
      @xRedisDbMock.should_receive('sismember').with('test_type:1:set_date', str)
      @xRedisDbMock.should_receive('smembers').with('test_type:1:set_date').and_return([str])
      @x.set_date << data
      @x.set_date.delete(data)
      @x.set_date.include?(data)
      @x.set_date.members[0].should be_kind_of(DateTime)
    end

    it "should handle empty members" do
      @xRedisDbMock.stub(:smembers).and_return(nil)
      @x.set_date.members.should == []
    end
  end

  context "increment/decrement" do
    class TestIncrements < Rhoconnect::StoreOrm
      field :foo, :integer
      field :bar, :string
      field :baz, :float
    end

    before do
      @redisMock = RSpec::Mocks::Mock.new
      @x = TestIncrements.with_key(1)
      @x.stub(:store).and_return(@redisMock)
    end

    it "should send INCR when #increment! is called on an integer" do
      @redisMock.should_receive(:update_count).with("test_increments:1:foo", 1)
      @x.increment!(:foo)
    end

    it "should send DECR when #decrement! is called on an integer" do
      @redisMock.should_receive(:update_count).with("test_increments:1:foo", -1)
      @x.decrement!(:foo)
    end

    it "should raise an ArgumentError when called on non-integers" do
      [:bar, :baz].each do |f|
        lambda{@x.increment!(f)}.should raise_error(ArgumentError)
        lambda{@x.decrement!(f)}.should raise_error(ArgumentError)
      end
    end
  end

  context "redis commands" do
    class TestCommands < Rhoconnect::StoreOrm
      field :foo
      list  :bar
      set   :sloppy
    end

    before(:each) do
      @redisMock = RSpec::Mocks::Mock.new
      @redisDbMock = RSpec::Mocks::Mock.new
      @x = TestCommands.with_key(1)
      @x.stub(:store).and_return(@redisMock)
      @redisMock.stub(:db).and_return(@redisDbMock)
    end

    it "should send GET on field read" do
      @redisMock.should_receive(:get_value).with('test_commands:1:foo')
      @x.foo
    end

    it "should send SET on field write" do
      @redisMock.should_receive(:put_value).with('test_commands:1:foo', 'bar')
      @x.foo = 'bar'
    end

    it "should send RPUSH on list <<" do
      @redisDbMock.should_receive(:rpush).with('test_commands:1:bar', 'bar')
      @x.bar << 'bar'
    end

    it "should send SADD on set <<" do
      @redisDbMock.should_receive(:sadd).with('test_commands:1:sloppy', 'bar')
      @x.sloppy << 'bar'
    end

    it "should delete separate fields" do
      @redisMock.should_receive(:delete_value).with('test_commands:1:foo')
      @x.delete :foo
    end

    it "should delete all field" do
      @redisMock.should_receive(:delete_value).with('test_commands:1:foo')
      @redisMock.should_receive(:delete_value).with('test_commands:1:rho__id')
      @redisMock.should_receive(:delete_value).with('test_commands:1:bar')
      @redisMock.should_receive(:delete_value).with('test_commands:1:sloppy')
      @x.delete
    end
  end
end
