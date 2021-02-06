# Natural20

A Ruby toolkit to create your own text based DnD 5th Edition RPG games or to quickly
test drive certain creature encounters if you are a DM.

Features:
 - Accurate DnD 5e ruleset implementation using the Open Game License
 - Line of Sight computation with Lighting simulation (dim, dark areas)
 - Simulation of doors, traps, treasure chests and cover
 - Rudimentary AI and pathfinding
 - Text based UI
 - Easily extensible to incorporate in your own games

 Supported Races:
 - Human
 - Elf
 - Halfling
 - More to come

 Supported Classes;
 - Fighter
 - Rogue
 - More to come

## Installation

- Install ruby 2.5 or later

Add this line to your application's Gemfile if you plan to use the game engine in an adventure of your own otherwise you can just clone this repository locally using git clone:

```ruby
gem 'natural_20'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install natural_20

## Usage

To quickly try this out, clone this repository, in the working folder start the game engine it will
load the default adventure included in this repository:

```
bin/nat20
```

See below for a description of the adventure

## Adventure Tutorial

The default adventure in this story is meant to showcase the game engine,
it contains a small dungeon with doors and traps as well as goblins and a dangerous owlbear.
you are to lead a party of 2 to steal the treasure behind one of those doors.

You can find the adventure specific files in the following locations:

char_classes/
characters/
items/
npcs/
races/
maps/game_map.yml
game.yml

These are all text readable for you to customize to your liking.

## Screenshots

![Screenshot from 2021-02-06 13-14-48](https://user-images.githubusercontent.com/949459/107109725-91212000-687d-11eb-8f59-3ecd2d5efa9e.png)
![Screenshot from 2021-02-06 13-15-13](https://user-images.githubusercontent.com/949459/107109730-941c1080-687d-11eb-94ad-565d4bde5cfd.png)
![Screenshot from 2021-02-06 13-15-37](https://user-images.githubusercontent.com/949459/107109733-95e5d400-687d-11eb-8928-53caad6f9b28.png)


## Creating your own adventures

You can generate a skeleton adventure using:

```
nat20author
```

A prompt based system will launch for you to create your own game.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/natural_20. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/natural_20/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Natural20 project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/natural_20/blob/master/CODE_OF_CONDUCT.md).
