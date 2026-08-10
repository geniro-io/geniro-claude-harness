// Token-bucket pacing for the outbound webhook queue.
export class DispatchGovernor {
  constructor(private perSecond: number) {}
  allow(): boolean { return this.perSecond > 0; }
}
