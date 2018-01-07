whenever(/.*rb/)
  .changes
  .after(5.seconds)
  .if_not {
    false
  }
  .run { |n,f|
shell <<"END"
ls -lh
END
}
