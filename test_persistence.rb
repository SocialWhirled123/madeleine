#!/usr/local/bin/ruby -w
#
# Copyright(c) 2003 Anders Bengtsson
#
# Based on the unit tests from Prevayler,
# Copyright(c) 2001-2003 Klaus Wuestefeld.
#

require 'madeleine'
require 'test/unit'

class AddingSystem
  attr_reader :total

  def initialize
    @total = 0
  end

  def add(value)
    @total += value
    @total
  end
end

class Addition

  attr_reader :value

  def initialize(value)
    @value = value
  end

  def execute(system)
    system.add(@value)
  end
end


class PersistenceTest < Test::Unit::TestCase

  def setup
    @prevaylers = []
    @prevayler = nil
  end

  def verify(expected_total)
    assert_equal(expected_total, prevalence_system().total(), "Total")
  end

  def prevalence_system
    @prevayler.system
  end

  def prevalence_base
    "PrevalenceBase"
  end

  def clear_prevalence_base
    @prevaylers.each {|prevayler|
      prevayler.take_snapshot
    }
    @prevaylers.clear
    delete_prevalence_files(prevalence_base())
  end

  def delete_prevalence_files(directory_name)
    return unless File.exist?(directory_name)
    Dir.foreach(directory_name) {|file_name|
      next if file_name == '.'
      next if file_name == '..'
      assert(File.delete(directory_name + File::SEPARATOR + file_name) == 1,
                  "Unable to delete #{file_name}")
    }
  end

  def crash_recover
    @prevayler =
      Madeleine::SnapshotPrevayler.new(AddingSystem.new, prevalence_base())
    @prevaylers << @prevayler
  end

  def snapshot
    @prevayler.take_snapshot
  end

  def add(value, expected_total)
    total = @prevayler.execute_command(Addition.new(value))
    assert_equal(expected_total, total, "Total")
  end

  def verify_snapshots(expected_count)
    count = 0
    Dir.foreach(prevalence_base) {|name|
      if name =~ /\.snapshot$/
        count += 1
      end
    }
    assert_equal(expected_count, count, "snapshots")
  end

  def test_main
    clear_prevalence_base

    # There is nothing to recover at first.
    # A new system will be created.
    crash_recover

    crash_recover
    add(40,40)
    add(30,70)
    verify(70)

    crash_recover
    verify(70)

    add(20,90)
    add(15,105)
    verify_snapshots(0)
    snapshot
    verify_snapshots(1)
    snapshot
    verify_snapshots(2)
    verify(105)

    crash_recover
    snapshot
    add(10,115)
    snapshot
    add(5,120)
    add(4,124)
    verify(124)

    crash_recover
    add(3,127)
    verify(127)

    verify_snapshots(4)

    clear_prevalence_base
    snapshot
		
    crash_recover
    add(10,137)
    add(2,139)
    crash_recover
    verify(139)
  end
end

class NumberedFileTest < Test::Unit::TestCase

  def test_main
    target = Madeleine::NumberedFile.new(File::SEPARATOR + "foo", "bar", 321)
    assert_equal(File::SEPARATOR + "foo" + File::SEPARATOR +
                 "000000000000000000321.bar",
                 target.name)
  end
end

class TimeTest < Test::Unit::TestCase

  def test_clock
    target = Madeleine::Clock::Clock.new
    assert_equal(0, target.time.to_i)
    assert_equal(0, target.time.usec)

    t1 = Time.at(10000)
    target.forward_to(t1)
    assert_equal(t1, target.time)
    t2 = Time.at(20000)
    target.forward_to(t2)
    assert_equal(t2, target.time)

    assert_nothing_raised() {
      target.forward_to(t2)
    }
    assert_raises(RuntimeError) {
      target.forward_to(t1)
    }
  end

  def test_time_actor
    @forward_calls = 0
    @last_time = Time.at(0)

    target = Madeleine::Clock::TimeActor.launch(self, 0.01)
    sleep(0.1)
    assert(@forward_calls > 1)
    target.destroy
  end

  # Self-shunt
  def execute_command(command)
    mock_system = self
    command.execute(mock_system)
  end

  # Self-shunt
  def forward_clock_to(time)
    if time <= @last_time
      raise "non-monotonous time"
    end
    @last_time = time
    @forward_calls += 1
  end

  def test_clocked_system
    target = Madeleine::Clock::ClockedSystem.new
    assert_equal(Time.at(0), target.time)
    t1 = Time.at(10000)
    target.forward_clock_to(t1)
    assert_equal(t1, target.time)

    reloaded_target = Marshal.load(Marshal.dump(target))
    assert_equal(t1, reloaded_target.time)
  end
end

class CommandLogTest < Test::Unit::TestCase

  def setup
    @target = Madeleine::CommandLog.new(".", 4711)
  end

  def teardown
    File.delete("000000000000000004711.command_log")
  end

  def test_logging
    f = open("000000000000000004711.command_log", 'r')
    assert(f.stat.file?)
    @target.store(Addition.new(7))
    read_command = Marshal.load(f)
    assert_equal(Addition, read_command.class)
    assert_equal(7, read_command.value)
    assert(f.eof?)
    @target.store(Addition.new(3))
    read_command = Marshal.load(f)
    assert_equal(3, read_command.value)
  end
end


suite = Test::Unit::TestSuite.new("Madeleine")
suite << CommandLogTest.suite
suite << NumberedFileTest.suite
suite << PersistenceTest.suite
suite << TimeTest.suite

require 'test/unit/ui/console/testrunner'
Test::Unit::UI::Console::TestRunner.run(suite)
