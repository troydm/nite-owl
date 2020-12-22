# Nite::Owl [![Gem Version](https://badge.fury.io/rb/nite-owl.svg)](https://badge.fury.io/rb/nite-owl) [![Build Status](https://travis-ci.org/troydm/nite-owl.png?branch=master)](https://travis-ci.org/troydm/nite-owl)

Nite Owl watches over your files and executes commands if anything happens to them, it's like [guard](https://github.com/guard/guard) on a super diet!
Supports linux and macos only and depends only on rb-fsevent and rb-inotify.

## Installation

To install just run this command:

    $ gem install nite-owl

## Usage

Create Niteowl.rb configuration file inside a directory you want to watch over and the run nite-owl.
See example Niteowl.rb configuration file.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/troydm/nite-owl.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
