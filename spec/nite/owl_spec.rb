RSpec.describe Nite::Owl do
  it "has a version number" do
    expect(Nite::Owl::VERSION).not_to be nil
  end

  it "cd command can change working directory and pwd" do
    prev_dir = pwd
    cd "spec"
    expect(File.basename(pwd)).to eq("spec")
    cd prev_dir
  end

  it "can execute shell commands and capture their output" do
    s = shell "ls -lh"
    expect(s).to include("total")
    expect(s).to include("spec")
    expect(s).to include("Gemfile")
    expect(s).to include("Rakefile")
  end

  it "can get the pid of running process" do
    pid = Process.pid
    expect(process("rspec")).to include(pid)
  end
  it "can help working with Time" do
    expect(10.milliseconds).to eq(0.01)
    expect(10.seconds).to eq(10.0)
    expect(10.minutes).to eq(600.0)
    expect(10.hours).to eq(36000.0)
  end
end
RSpec.describe Nite::Owl::Action do
  it "can have tree of actions" do
    c = 0
    nroot = Nite::Owl::Action.new
    root = Nite::Owl::Action.new
    nroot.add(root)
    root.run { c+=1 }
    l = Nite::Owl::Action.new
    l.run { c+=1 }
    r = Nite::Owl::Action.new
    r.run { c+=1 }
    rl = Nite::Owl::Action.new
    rl.run { c+=1 }
    rr = Nite::Owl::Action.new
    rr.run { c+=1 }
    expect(r.add(rl)).to eq(rl)
    expect(r.add(rr)).to eq(rr)
    expect(root.add(l)).to eq(l)
    expect(root.add(r)).to eq(r)
    expect(l.parent).to eq(root)
    expect(l.root).to eq(root)
    expect(r.parent).to eq(root)
    expect(r.root).to eq(root)
    expect(rl.root).to eq(root)
    expect(rr.root).to eq(root)
    expect(rl.parent).to eq(r)
    expect(rr.parent).to eq(r)
    expect(root.parent).to eq(nroot)
    expect(root.contains?(l)).to be_truthy
    expect(root.contains?(r)).to be_truthy
    expect(root.contains?(rr)).to be_truthy
    expect(root.contains?(rl)).to be_truthy
    expect(r.contains?(rr)).to be_truthy
    expect(r.contains?(rl)).to be_truthy
    expect(l.contains?(rr)).to be_nil
    expect(l.contains?(rl)).to be_nil
    root.call(nil,nil)
    expect(c).to eq(5)
    c = 0
    root.remove(rl)
    root.remove(rr)
    expect(root.contains?(rr)).to be_nil
    expect(root.contains?(rl)).to be_nil
    root.call(nil,nil)
    expect(c).to eq(3)
  end
  it "can defer their execution" do
    c = 0
    root = Nite::Owl::Action.new
    root.run { 
      c+=1 
    }
    root.defer(nil,nil)
    expect(c).to eq(0)
    Nite::Owl::Action.call_all_deferred_actions()
    expect(c).to eq(1)
    Nite::Owl::Action.call_all_deferred_actions()
    expect(c).to eq(2)
    root.undefer
    Nite::Owl::Action.call_all_deferred_actions()
    expect(c).to eq(2)
  end
  it "can delay their execution" do
    c = 0
    root = Nite::Owl::Action.new
    root.run { 
      delay(1)
      c+=1 
    }
    root.call(nil,nil)
    expect(c).to eq(0)
    sleep(1)
    root.call(nil,nil)
    expect(c).to eq(1)
  end
end
RSpec.describe Nite::Owl::After do
  it "can execute actions only after some delay" do
    c = 0
    after = Nite::Owl::After.new(2)
    after.run { c+=1 }
    after.call(nil,nil)
    after.call(nil,nil)
    after.call(nil,nil)
    expect(c).to eq(0)
    sleep(2)
    after.call(nil,nil)
    expect(c).to eq(1)
    after.call(nil,nil)
    after.call(nil,nil)
    expect(c).to eq(1)
    sleep(2)
    after.call(nil,nil)
    expect(c).to eq(2)
  end
end
RSpec.describe Nite::Owl::OnlyIf do
  it "can execute actions only if condition is met" do
    j = 0
    c = 0
    only_if = Nite::Owl::OnlyIf.new(Proc.new { j > 0 })
    only_if.run { c+= 1 }
    only_if.call(nil,nil)
    expect(c).to eq(0)
    j = 1
    only_if.call(nil,nil)
    expect(c).to eq(1)
  end
end
RSpec.describe Nite::Owl::IfNot do
  it "can execute actions only if condition is not met" do
    j = 1
    c = 0
    if_not = Nite::Owl::IfNot.new(Proc.new { j > 0 })
    if_not.run { c+= 1 }
    if_not.call(nil,nil)
    expect(c).to eq(0)
    j = 0
    if_not.call(nil,nil)
    expect(c).to eq(1)
  end
end
RSpec.describe Nite::Owl::HasFlags do
  it "can execute actions only if certain flags are present" do
    c = 0
    has_flags = Nite::Owl::HasFlags.new([:b,:c])
    has_flags.run { c+= 1 }
    has_flags.call(nil,[:a])
    expect(c).to eq(0)
    has_flags.call(nil,[:b])
    expect(c).to eq(1)
    has_flags.call(nil,[:c])
    expect(c).to eq(2)
  end
end
RSpec.describe Nite::Owl::NameIs do
  it "can execute actions only if name matches either regexp pattern or fnmatch pattern" do
    c = 0
    name_is = Nite::Owl::NameIs.new(["*.b","*.c"])
    name_is.run { c+= 1 }
    name_is.call("test.a",nil)
    expect(c).to eq(0)
    name_is.call("test.b",nil)
    expect(c).to eq(1)
    name_is.call("test.c",nil)
    expect(c).to eq(2)
    name_is = Nite::Owl::NameIs.new([/.*b/,/.*c/])
    name_is.run { c+= 1 }
    name_is.call("test.a",nil)
    expect(c).to eq(2)
    name_is.call("test.b",nil)
    expect(c).to eq(3)
    name_is.call("test.c",nil)
    expect(c).to eq(4)
  end
end
