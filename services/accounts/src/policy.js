export const booleans = new Set([
  'appIconFollowsTheme', 'automaticSeasonalThemes', 'seasonalHalloween', 'seasonalChristmas',
  'weatherOnLiveTab', 'tileShowLabels', 'playerColorTinting', 'useMusicVisualizer',
  'showShuffleAndRepeat', 'coloredSpectrogram', 'showBatteryIndicator', 'showBatteryPercentage',
  'showPowerStatusIcons', 'hideBatteryWhenAbsent', 'hideCompletedReminders',
]);
export const choices = {
  appTheme: ['system', 'autumn', 'halloween', 'christmas', 'winter', 'easter',
    'springBloom', 'summerCoast', 'nightSky', 'botanical', 'desertDusk', 'graphite',
    'starWars', 'starWarsDarkSide', 'starWarsLuke', 'starWarsObiWan', 'starWarsAhsoka',
    'starWarsYoda', 'starWarsMaceWindu', 'starWarsRey', 'starWarsVader', 'starWarsMaul',
    'whiteHouse', 'whiteHouseOvalOffice', 'whiteHouseEastRoom', 'whiteHouseBlueRoom',
    'whiteHouseRepublican', 'whiteHouseRepublicanOvalOffice', 'whiteHouseRepublicanEastRoom', 'whiteHouseRepublicanBlueRoom',
    'whiteHouseDemocrat', 'whiteHouseDemocratOvalOffice', 'whiteHouseDemocratEastRoom', 'whiteHouseDemocratBlueRoom',
    'whiteHouseChristmas', 'whiteHouseChristmasOvalOffice', 'whiteHouseChristmasEastRoom', 'whiteHouseChristmasBlueRoom',
    'whiteHouseRepublicanChristmas', 'whiteHouseRepublicanChristmasOvalOffice', 'whiteHouseRepublicanChristmasEastRoom', 'whiteHouseRepublicanChristmasBlueRoom',
    'whiteHouseDemocratChristmas', 'whiteHouseDemocratChristmasOvalOffice', 'whiteHouseDemocratChristmasEastRoom', 'whiteHouseDemocratChristmasBlueRoom'],
  appIconVariant: ['standard', 'autumn', 'halloween', 'christmas', 'winter', 'easter', 'whiteHouse',
    'whiteHouseRepublican', 'whiteHouseDemocrat', 'whiteHouseRepublicanChristmas', 'whiteHouseDemocratChristmas'],
  seasonHemisphere: ['northern', 'southern'],
  batteryPresentation: ['original', 'enhanced'],
  batteryIndicatorDisplay: ['iconOnly', 'percentageOnly', 'both'],
};
export const lists = new Set(['homeWidgetOrder', 'hiddenHomeWidgets']);
export const widgets = new Set(['music', 'calendar', 'weather', 'quickActions']);
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export function validDocument(value) {
  if (!record(value) || Object.keys(value).sort().join(',') !== 'schemaVersion,values' ||
      value.schemaVersion !== 1 || !record(value.values) || Object.keys(value.values).length > 40 ||
      new TextEncoder().encode(JSON.stringify(value)).length > 8192) return false;
  return Object.entries(value.values).every(([key, item]) => {
    if (booleans.has(key)) return typeof item === 'boolean';
    if (Object.hasOwn(choices, key)) return typeof item === 'string' && choices[key].includes(item);
    if (lists.has(key)) return Array.isArray(item) && item.length <= 4 &&
      new Set(item).size === item.length && item.every(entry => widgets.has(entry));
    return false;
  });
}
