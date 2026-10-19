function img = ss_simulatedPhoto()
%SS_SIMULATEDPHOTO  Generate a simple synthetic landscape "photo" (RGB, 0..1).
%   Stands in for a real camera frame - no camera hardware is used.
H = 240;  W = 320;
[X, Y] = meshgrid(1:W, 1:H);

top = [0.30 0.55 0.95];  bottom = [0.85 0.92 1.00];
frac = Y / H;
img = zeros(H, W, 3);
for k = 1:3
    img(:, :, k) = top(k) * (1 - frac) + bottom(k) * frac;
end

% Sun at a random position
cx = 50 + 220 * rand;  cy = 45 + 25 * rand;
sun = (X - cx).^2 + (Y - cy).^2 < 22^2;
img = paint(img, sun, [1.00 0.90 0.30]);

% Two layers of hills
far  = Y > 150 + 20 * sin(2 * pi * X / (180 + 80 * rand) + 2 * pi * rand);
img  = paint(img, far, [0.35 0.55 0.40]);
near = Y > 185 + 12 * sin(2 * pi * X / (120 + 60 * rand) + 2 * pi * rand);
img  = paint(img, near, [0.20 0.62 0.25]);

img = min(max(img, 0), 1);
end

function img = paint(img, mask, rgb)
for k = 1:3
    ch = img(:, :, k);
    ch(mask) = rgb(k);
    img(:, :, k) = ch;
end
end
