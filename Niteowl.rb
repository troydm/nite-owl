whenever(/.*rb/)
  .changes
  .after(5.seconds)
  .if_not {
    false
  }
  .run do |n,f|
    puts "Hello World"
    cancel
    shell "ls -lh"
  end
  .also.run do |n,f|
    puts "Change detected "+n.to_s+" "+f.to_s
  end
