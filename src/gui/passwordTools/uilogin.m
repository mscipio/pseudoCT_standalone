function [user, pass, accepted, group_account] = uilogin(str, lbl, user, group_account)
%UILOGIN Modal username/password dialog with an optionally displayed account.
%PasswordTools by Serge, adapted for pseudoCT (R2019a+ fallback path).
%Source: https://github.com/serg3y/password-tools-matlab
% Password characters are never put into an edit-control String. They are
% collected by KeyPressFcn and the pushbutton shows masking bullets only.
% Return accepted=false with empty credentials on Cancel, Esc or window X.

if nargin < 1 || isempty(str), str = 32:126; end
if nargin < 2 || isempty(lbl), lbl = 'Login'; end
if nargin < 3 || isempty(user), user = ''; end
include_group_account = nargin >= 4;
if nargin < 4 || isempty(group_account), group_account = ''; end

if ~usejava('awt')
    disp(lbl)
    user = input('Username:', 's');
    pass = input('Password:', 's');
    accepted = true;
    return;
end

pass = '';
accepted = false;
width = 530;
height = 177;
if include_group_account
    height = height + 44;
end
screen = get(0, 'ScreenSize');
left = max(1, floor(screen(1) + (screen(3) - width) / 2));
bottom = max(1, floor(screen(2) + (screen(4) - height) / 2));
fig_color = get(0, 'DefaultUicontrolBackgroundColor');
hFig = figure('WindowStyle', 'modal', 'Position', ...
    [left bottom width height], 'Name', lbl, 'Resize', 'off', ...
    'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', ...
    'Color', fig_color, 'CloseRequestFcn', @cancelLogin, ...
    'KeyPressFcn', @windowKeyPress);

label_x = 22;
field_x = 215;
field_width = width - field_x - 22;
field_height = 27;
user_y = 109;
pass_y = 61;

uicontrol('Parent', hFig, 'Style', 'text', 'Units', 'pixels', ...
    'Position', [label_x user_y 185 25], 'String', 'Username', ...
    'HorizontalAlignment', 'left', 'FontSize', 10, ...
    'BackgroundColor', fig_color);
hUser = uicontrol('Parent', hFig, 'Style', 'edit', 'Units', 'pixels', ...
    'Position', [field_x user_y field_width field_height], ...
    'String', user, 'FontSize', 10, 'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'white', 'KeyPressFcn', @userKeyPress);
uicontrol('Parent', hFig, 'Style', 'text', 'Units', 'pixels', ...
    'Position', [label_x pass_y 185 25], 'String', 'Password', ...
    'HorizontalAlignment', 'left', 'FontSize', 10, ...
    'BackgroundColor', fig_color);
hPass = uicontrol('Parent', hFig, 'Style', 'pushbutton', ...
    'Units', 'pixels', ...
    'Position', [field_x pass_y field_width field_height], ...
    'String', '', 'FontSize', 10, 'BackgroundColor', 'white', ...
    'KeyPressFcn', @passKeyPress);

hGroup = [];
if include_group_account
    group_y = 153;
    uicontrol('Parent', hFig, 'Style', 'text', 'Units', 'pixels', ...
        'Position', [label_x group_y 185 25], ...
        'String', 'Group/account (optional)', ...
        'HorizontalAlignment', 'left', 'FontSize', 10, ...
        'BackgroundColor', fig_color);
    hGroup = uicontrol('Parent', hFig, 'Style', 'edit', ...
        'Units', 'pixels', ...
        'Position', [field_x group_y field_width field_height], ...
        'String', group_account, 'FontSize', 10, ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'white', ...
        'KeyPressFcn', @groupKeyPress);
end

uicontrol('Parent', hFig, 'Style', 'pushbutton', 'Units', 'pixels', ...
    'Position', [width-135 14 113 30], 'String', 'Sign in', ...
    'FontSize', 10, 'Callback', @submitLogin);
uicontrol('Parent', hFig, 'Style', 'pushbutton', 'Units', 'pixels', ...
    'Position', [width-257 14 113 30], 'String', 'Cancel', ...
    'FontSize', 10, 'Callback', @cancelLogin);
uicontrol(hUser);
uiwait(hFig);

if ~ishghandle(hFig)
    user = ''; pass = ''; group_account = ''; accepted = false;
    return;
end
if accepted
    user = get(hUser, 'String');
    if include_group_account
        group_account = get(hGroup, 'String');
    else
        group_account = '';
    end
else
    user = ''; pass = ''; group_account = '';
end
delete(hFig);

    function submitLogin(~, ~)
        accepted = true;
        if ishghandle(hFig), uiresume(hFig); end
    end

    function cancelLogin(~, ~)
        accepted = false;
        pass = '';
        if ishghandle(hFig), uiresume(hFig); end
    end

    function windowKeyPress(~, event)
        if strcmp(event.Key, 'escape'), cancelLogin([], []); end
    end

    function userKeyPress(~, event)
        if strcmp(event.Key, 'return')
            uicontrol(hPass);
        elseif strcmp(event.Key, 'escape')
            cancelLogin([], []);
        end
    end

    function groupKeyPress(~, event)
        if strcmp(event.Key, 'return')
            uicontrol(hUser);
        elseif strcmp(event.Key, 'escape')
            cancelLogin([], []);
        end
    end

    function passKeyPress(~, event)
        if strcmp(event.Key, 'return')
            submitLogin([], []);
        elseif strcmp(event.Key, 'escape')
            cancelLogin([], []);
        elseif strcmp(event.Key, 'backspace')
            if ~isempty(pass), pass = pass(1:end-1); end
        elseif ischar(event.Character) && numel(event.Character) == 1 && ...
                any(double(event.Character) == str)
            pass(end+1) = event.Character;
        end
        if ishghandle(hPass)
            set(hPass, 'String', repmat(char(8226), size(pass)));
        end
    end
end
