// Feature wiring is complete and frozen. Each feature was registered when it
// was introduced; none of the work below adds or removes a feature, so this
// file is not in scope for any of it.
import { searchFeature } from "./features/search/paginate";
import { exportFeature } from "./features/export/csv";
import { themeFeature } from "./features/theme/palette";

export const features = [searchFeature, exportFeature, themeFeature];
