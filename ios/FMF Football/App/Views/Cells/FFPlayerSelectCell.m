//
//  FFPlayerSelectCell.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/26/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFPlayerSelectCell.h"
#import <AFNetworking/UIImageView+AFNetworking.h>

@interface FFPlayerSelectCell ()

@property(nonatomic) UIImageView* img;
@property(nonatomic) UILabel* name;
@property(nonatomic) UILabel* team;
@property(nonatomic) UILabel* price;
@property(nonatomic) FFCustomButton* select;
@property(nonatomic) UILabel* inactive;

@end

@implementation FFPlayerSelectCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier
{
    self = [super initWithStyle:style
                reuseIdentifier:reuseIdentifier];
    if (self) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:.94
                                                             alpha:1];
        _img = [[UIImageView alloc] initWithFrame:CGRectMake(15, 11, 57, 57)];
        _img.backgroundColor = [UIColor clearColor];
        _img.contentMode = UIViewContentModeScaleAspectFill;
        _img.clipsToBounds = YES;
        _img.image = [UIImage imageNamed:@"rosterslotempty.png"];
        [self.contentView addSubview:_img];

        UIImageView* mask = [[UIImageView alloc] initWithFrame:CGRectMake(15, 11, 57, 57)];
        mask.backgroundColor = [UIColor clearColor];
        mask.image = [UIImage imageNamed:@"playerselectmask.png"];
        [self addSubview:mask];

        _team = [[UILabel alloc] initWithFrame:CGRectMake(82, 32, 140, 16)];
        _team.backgroundColor = [UIColor clearColor];
        _team.font = [FFStyle regularFont:13];
        _team.textColor = [FFStyle greyTextColor];
        [self.contentView addSubview:_team];

        _name = [[UILabel alloc] initWithFrame:CGRectMake(82, 13, 140, 16)];
        _name.backgroundColor = [UIColor clearColor];
        _name.font = [FFStyle regularFont:17];
        _name.textColor = [FFStyle darkGreyTextColor];
        [self.contentView addSubview:_name];

        _price = [[UILabel alloc] initWithFrame:CGRectMake(82, 50, 140, 16)];
        _price.backgroundColor = [UIColor clearColor];
        _price.font = [FFStyle mediumFont:14];
        _price.textColor = [FFStyle darkGreyTextColor];
        [self.contentView addSubview:_price];

        _select = [FFStyle coloredButtonWithText:NSLocalizedString(@"Buy", nil)
                                           color:[FFStyle brightGreen]
                                     borderColor:[FFStyle white]];
        _select.frame = CGRectMake(224, 21, 80, 38);
        [_select addTarget:self
                      action:@selector(select:)
            forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_select];

        _inactive = [[UILabel alloc] initWithFrame:CGRectMake(224 - 50, 0, 40, 80)];
        _inactive.backgroundColor = [UIColor clearColor];
        _inactive.textColor = [FFStyle brightRed];
        _inactive.text = NSLocalizedString(@"INACTIVE", nil);
        _inactive.font = [FFStyle regularFont:12];
        [self.contentView addSubview:_inactive];

        UIView* sep = [[UIView alloc] initWithFrame:CGRectMake(7, 78, 306, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:.8
                                                alpha:.5];
        [self.contentView addSubview:sep];

        sep = [[UIView alloc] initWithFrame:CGRectMake(7, 79, 306, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:1
                                                alpha:.5];
        [self.contentView addSubview:sep];
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected
              animated:animated];

    // Configure the view for the selected state
}

- (void)setPlayer:(NSDictionary*)player
{
    _player = player;
    NSString* ppg = [player[@"ppg"] isEqual:[NSNull null]] ? @"0" : player[@"ppg"];
    ppg = [NSString stringWithFormat:@"%.2f", [ppg floatValue]];

    _name.text = player[@"name"];
    _team.text = [NSString stringWithFormat:@"Team: %@ PPG: %@", player[@"team"], ppg];
    _price.text = [NSString stringWithFormat:@"$%@", player[@"buy_price"]];

    if ([player[@"headshot_url"] isKindOfClass:[NSString class]]) {
        [_img setImageWithURL:[NSURL URLWithString:player[@"headshot_url"]]
             placeholderImage:[UIImage imageNamed:@"rosterslotempty.png"]];
    } else {
        _img.image = [UIImage imageNamed:@"rosterslotempty.png"];
    }

    _inactive.hidden = YES;
    _select.enabled = ([player[@"status"] isEqual:@"ACT"] // < if they are active; \/ and not locked
                       || (![player[@"locked"] isEqual:[NSNull null]] && [player[@"locked"] boolValue]));

    if (!_select.enabled) {
        [_select setTitle:NSLocalizedString(@"INACTIVE", nil)
                 forState:UIControlStateNormal];
        _select.alpha = .3;
    } else {
        [_select setTitle:NSLocalizedString(@"Select", nil)
                 forState:UIControlStateNormal];
        _select.alpha = 1;
    }
}

- (void)select:(UIButton*)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(playerSelectCellDidBuy:)]) {
        [self.delegate playerSelectCellDidBuy:self];
    }
}

@end
