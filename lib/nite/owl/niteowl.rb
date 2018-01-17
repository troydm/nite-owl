require 'open3'

# Nite Owl DSL
def quote(path)
  if path.include? " "
    "\"#{path}\""
  else
    path
  end
end

def cd(dir)
  Dir.chdir quote(dir)
  puts "cd #{dir}"
end

def pwd
  d = Dir.pwd
  puts "pwd: #{d}"
  d
end

def whenever(files)
  if files.is_a?(String) or files.is_a?(Regexp)
    files = [files]
  end
  Nite::Owl::NiteOwl.instance.whenever(files)
end

def delay(time)
  Nite::Owl::NiteOwl.instance.current_action().delay(time)
end

# Run command in shell and redirect it's output to stdout and stderr
def shell(command,options={:verbose => false,:silent => false,:stdin => nil})
  stdout = ""
  stderr = ""
  verbose = options[:verbose]
  silent = options[:silent]
  stdin = options[:stdin]
  if verbose
    puts "Executing: #{command}"
  end
  Open3.popen3(command) do |i,o,e,t|
    stdin_i = 0
    stdin_open = stdin != nil
    stdout_buffer = ""
    stderr_buffer = ""
    stdout_open = true
    stderr_open = true
    stdout_ch = nil
    stderr_ch = nil
    while stdout_open or stderr_open or stdin_open
      if stdin_open
        begin
          p stdin
          i.write(stdin)
          i.close_write
          stdin_open = false
          #c = i.write_nonblock(stdin[stdin_i])
          #if c > 0
          #  stdin_i += 1
          #  if stdin_i == stdin.size
          #    i.close_write
          #    stdin_open = false
          #  end
          #end
        rescue IO::WaitWritable
          IO.select([i])
          puts "retry writeable"
          retry
        rescue EOFError
          stdin_open = false
        end
      end
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
        stdout += stdout_buffer+"\n"
        unless silent
          puts stdout_buffer
        end
        stdout_buffer = ""
      elsif stdout_ch != nil
        stdout_buffer << stdout_ch
      end
      stdout_ch = nil
      if stderr_ch == "\n" then
        stderr += stderr_buffer+"\n"
        unless silent
          STDERR.puts stderr_buffer
        end
        stderr_buffer = ""
      elsif stderr_ch != nil
        stderr_buffer << stderr_ch
      end
      stderr_ch = nil
    end
  end
  if stderr != ""
    return stdout, stderr
  else
    return stdout
  end
end

# get process pid(s)
def process(name,full=true)
  if full
    full = '-f '
  else
    full = ''
  end
  out,_ = Open3.capture2("/usr/bin/pgrep #{full}#{name}")
  if out == ''
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

    # special exception thrown by delay method
    class Delay < Exception
      attr_accessor :time
      def initialize(time)
        @time = time
      end
    end

    $current_action = nil
    $deferred_actions = {}

    class Action
      attr_accessor :parent
      def initialize
        @actions = []
        @parent=nil
        @delay=nil
      end
      def current_action
        $current_action
      end
      def defer(name,flags)
        unless $deferred_actions.has_key?(self)
          $deferred_actions[self] = [name,flags] 
        end
      end
      def undefer
        $deferred_actions.delete(self)
      end
      def self.call_all_deferred_actions
        unless $deferred_actions.empty?
          $deferred_actions.dup.each do |a,event|
            a.call(event[0],event[1])
          end
        end
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
        @actions.delete_if { |a| a == action }
        @actions.each { |a| a.is_a?(Action) and a.remove(action) }
        action
      end
      def run(&block)
        add(block)
        self
      end
      def call(name,flags)
        $current_action = self
        @actions.each do |n|
          begin
            n.call(name,flags)
          rescue Delay => d
            handle_delay(d)
            defer(name,flags)
          rescue Exception => e
            STDERR.puts e.message
            STDERR.puts e.backtrace
          end
        end
      end
      def delay(time)
        if @delay
          if Time.now >= @delay
            @delay = nil
          else
            raise Delay.new(0)
          end
        else
          raise Delay.new(time)
        end
      end
      def handle_delay(d)
        unless @delay
          @delay = Time.now + d.time
        end
      end
      def only_once
        run { root.remove(self) }
      end
      def after(delay)
        add(After.new(delay))
      end
      def created
        add(HasFlags.new([:create]))
      end
      def modified
        add(HasFlags.new([:modify]))
      end
      def deleted
        add(HasFlags.new([:delete]))
      end
      def renamed
        add(HasFlags.new([:rename]))
      end
      def changes
        add(HasFlags.new([:create,:delete,:modify,:rename]))
      end
      def only_if(&block)
        add(OnlyIf.new(block))
      end
      def if_not(&block)
        add(IfNot.new(block))
      end
    end

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
        $current_action = self
        begin
          unless @time
            @time = Time.now.to_f
          end
          if expired?
            undefer()
            @time = nil
          elsif predicate?(name,flags)
            super(name,flags)
            undefer()
            @time = nil
          else
            defer(name,flags)
          end
        rescue Delay => d
          handle_delay(d)
          defer(name,flags)
        rescue Exception => e
          STDERR.puts e.message
          STDERR.puts e.backtrace
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

    class NameIs < Action
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
        if File.file?("Niteowl") && File.readable?("Niteowl")
          load "Niteowl"
        else
          puts "No Niteowl file found in: #{dir}"
        end
        if @actions.empty?
          puts "No actions configured"
        end
      end

      def whenever(files)
        add(NameIs.new(files))
      end

      def start
        @workers_thread = Thread.new {
          begin
            interval = 0.1
            event_interval = 0.5
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
                    puts e.backtrace
                  end
                end
                events.clear
                last_event_time = nil
              end
              Action.call_all_deferred_actions()
              delay = next_time - Time.now.to_f
              if delay > 0
                sleep(delay)
              end
              next_time = Time.now.to_f+interval
            end
          rescue Exception => e
            puts e.message
            puts e.backtrace
          end
        }
        # start platform specific notifier
        pwd = Dir.pwd
        if RUBY_PLATFORM =~ /linux/
          require 'rb-inotify'
          puts "Nite Owl watching: #{pwd}"
          notifier = INotify::Notifier.new
          notifier.watch(pwd, :recursive, :modify, :create, :delete, :move) do |event|
            name = event.absolute_name.slice(pwd.size+1,event.absolute_name.size-pwd.size)
            flags = event.flags do |f|
              if f == :moved_to or f == :moved_from
                :rename
              else
                f
              end
            end
            @queue << [name,flags]
          end
          begin
            notifier.run
          rescue Interrupt => e
          end
        elsif RUBY_PLATFORM =~ /darwin/
          require 'rb-fsevent'
          puts "Nite Owl watching: #{pwd}"
          fsevent = FSEvent.new
          fsevent.watch pwd,{:file_events => true} do |paths, event_meta|
            event_meta['events'].each do |event|
              name = event['path']
              name = name.slice(pwd.size+1,name.size-pwd.size)
              flags = event['flags'].map do |f|
                if f == 'ItemCreated'
                  :create
                elsif f == 'ItemModified'
                  :modify
                elsif f == 'ItemRemoved'
                  :delete
                elsif f == 'ItemRenamed'
                  :rename
                end
              end.keep_if {|f| f}
              @queue << [name,flags]
            end
          end
          fsevent.run
        else
          puts "Platform unsupported"
          exit(1)
        end
      end
    end
  end
end
