require 'open3'

# Nite Owl DSL
def whenever(files)
  if files.is_a?(String) or files.is_a?(Regexp)
    files = [files]
  end
  Nite::Owl::NiteOwl.instance.whenever(files)
end

# Run command in shell and redirect it's output to stdout and stderr
def shell(command)
  Open3.popen3(command) do |i,o,e,t|
    stdout_buffer = ""
    stderr_buffer = ""
    stdout_open = true
    stderr_open = true
    stdout_ch = nil
    stderr_ch = nil
    while stdout_open or stderr_open
      if stdout_open
        begin
          stdout_ch = o.read_nonblock(1)
        rescue IO::WaitReadable
          IO.select([o])
          retry
        rescue EOFError
          stdout_open = false
        end
      end
      if stderr_open
        begin
          stderr_ch = e.read_nonblock(1)
        rescue IO::WaitReadable
          IO.select([e])
          retry
        rescue EOFError
          stderr_open = false
        end
      end
      if stdout_ch == "\n" then
        puts stdout_buffer
        stdout_buffer = ""
      elsif stdout_ch != nil
        stdout_buffer << stdout_ch
      end
      stdout_ch = nil
      if stderr_ch == "\n" then
        STDERR.puts stderr_buffer
        stderr_buffer = ""
      elsif stderr_ch != nil
        stderr_buffer << stderr_ch
      end
      stderr_ch = nil
    end
  end
end

# get process pid(s)
def process(name)
  out,_ = Open3.capture2("pgrep -f #{name}")
  if out == ""
    nil
  else
    pids = []
    out.lines.each do |pid|
      pids << pid.to_i
    end
    if pids.size == 1
      pids[0]
    else
      pids
    end
  end
end

# kill process
def kill(pids,signal=15)
  if pids.is_a?(Array)  
    pids.each do |pid|
      Process.kill(signal,pid)
    end
  else
    Process.kill(signal,pids)
  end
end

module Nite
  module Owl
    require 'singleton'
    require 'time'

    class ::Fixnum
      def milliseconds
        self/1000.0
      end
      def seconds
        to_f
      end
      def minutes
        self*60.0
      end
      def hours
        self*3600.0
      end
    end

    class Action
      attr_accessor :parent
      def initialize
        @actions = []
        @parent=nil
      end
      def root
        r = self
        while r.parent
          r = r.parent
        end
        r
      end
      def add(action)
        @actions << action
        if action.is_a?(Action)
          action.parent = self
        end
        action
      end
      def contains?(action)
        @actions.find { |a| a == action or (a.is_a?(Action) and a.contains?(action)) }
      end
      def remove(action)
        @actions.delete_if { |a| a.contains?(action) }
        action
      end
      def run(&block)
        add(block)
        self
      end
      def call(name,flags)
        @actions.each { |n| n.call(name,flags) }
      end
      def only_once
        run { root.remove(self) }
      end
      def after(delay)
        add(After.new(delay))
      end
      def created
        add(HasFlags.new([:create,:moved_to]))
      end
      def modified
        add(HasFlags.new([:modify]))
      end
      def deleted
        add(HasFlags.new([:delete,:moved_from]))
      end
      def changes
        add(HasFlags.new([:create,:delete,:modify,:moved_to,:moved_from]))
      end
      def only_if(&block)
        add(OnlyIf.new(block))
      end
      def if_not(&block)
        add(IfNot.new(block))
      end
    end

    $predicate_actions = {}

    class PredicateAction < Action
      def initialize
        super()
        @time = nil
        @expires = nil
      end
      def predicate?(name,flags)
        true
      end
      def expired?
        @expires and @time and (@time+@expires) >= Time.now.to_f
      end
      def expires(delay)
        @expires = delay.to_f
        self
      end
      def call(name,flags)
        if not @time
          @time = Time.now.to_f
        end
        if expired?
          $predicate_actions.delete(self)
        elsif predicate?(name,flags) 
          super(name,flags)
          $predicate_actions.delete(self)
        else
          $predicate_actions[self] = [name,flags]
        end
      end
    end

    class After < PredicateAction
      def initialize(delay)
        super()
        @delay = delay.to_f
        @time = nil
      end
      def predicate?(name,flags)
        Time.now.to_f >= @time+@delay
      end
    end

    class OnlyIf < PredicateAction
      def initialize(block)
        super()
        @predicate = block
      end
      def predicate?(name,flags)
        @predicate.call(name,flags)
      end
    end

    class IfNot < PredicateAction
      def initialize(block)
        super()
        @predicate = block
      end
      def predicate?(name,flags)
        not @predicate.call(name,flags)
      end
    end

    class HasFlags < Action
      def initialize(flags)
        super()
        @flags = flags
      end
      def match?(flags)
        @flags.find { |f| flags.include?(f) }
      end
      def call(name,flags)
        match?(flags) && super(name,flags)
      end
    end

    class Whenever < Action
      def initialize(files)
        super()
        @files = files
      end
      def match?(file)
        @files.find do |pattern|
          if pattern.is_a?(Regexp)
            pattern.match(file) != nil
          else
            File.fnmatch?(pattern,file)
          end
        end
      end
      def call(name,flags)
        match?(name) && super(name,flags)
      end
    end

    class NiteOwl < Action
      include Singleton

      def initialize
        super()
        @workers_thread = nil
        @queue = Queue.new
      end

      def watch(dir)
        Dir.chdir dir
        if File.file?("watch.rb") && File.readable?("watch.rb")
          load "watch.rb"
        else
          puts "No watch.rb found in: #{dir}"
        end
        if @actions.empty?
          puts "No actions configured"
        end
      end

      def whenever(files)
        add(Whenever.new(files))
      end

      def start
        @workers_thread = Thread.new {
          interval = 0.1
          event_interval = 0.075
          last_event_time = nil
          next_time = Time.now.to_f+interval
          events = {}
          while true
            until @queue.empty?
              event = @queue.pop(true) rescue nil
              if event
                name = event[0]
                flags = event[1]
                if events[name]
                  new_flags = events[name] + flags
                  if new_flags == [:delete, :create, :modify]
                    new_flags = [:modify]
                  end
                  events[name] = new_flags
                else
                  events[name] = flags
                end
                last_event_time = Time.now.to_f
              end
            end
            if last_event_time && Time.now.to_f >= (last_event_time+event_interval)
              events.each do |name,flags|
                begin
                  Nite::Owl::NiteOwl.instance.call(name,flags.uniq)
                rescue Exception => e
                  puts e.message
                end
              end
              events.clear
              last_event_time = nil
            end
            if not $predicate_actions.empty?
              $predicate_actions.each do |a,event|
                a.call(event[0],event[1])
              end
            end
            delay = next_time - Time.now.to_f
            if delay > 0
              sleep(delay/1000.0)
            end
            next_time = Time.now.to_f+interval
          end
        }
        # start platform specific notifier
        if RUBY_PLATFORM =~ /linux/
          require 'rb-inotify'
          pwd = Dir.pwd
          puts "Nite Owl watching: #{pwd}"
          notifier = INotify::Notifier.new
          notifier.watch(Dir.pwd, :recursive, :modify, :create, :delete, :move) do |event|
            name = event.absolute_name.slice(pwd.size+1,event.absolute_name.size-pwd.size)
            @queue << [name,event.flags]
          end
          begin
            notifier.run
          rescue Interrupt => e
          end
        else
          puts "Platform unsupported"
          exit(1)
        end
      end
    end
  end
end
